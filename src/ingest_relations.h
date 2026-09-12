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
    return fieldChild( defineNode, NodeField::Value );
}

// the def's body node: the `body:` field for every function/class grammar, and — macro-edges round — a
// #define's `value:` (preproc_arg) replacement text. Adopting the value as the body gives a macro symbol a
// real signature/body split (sigEnd = replacement start), which is ALSO what makes graph.h's decl/def
// collapse treat an indexed macro as a DEFINITION (hasBody: endByte > sigEndByte) instead of a shadowable
// forward decl. Kept out of captureTagsFacts (the file's densest dispatch point) behind one call.
TSNode defBodyNodeOf( TSNode roleNode, SymKind kind ) noexcept
{
    TSNode body = fieldChild( roleNode, NodeField::Body );
    if( ts_node_is_null( body ) && kind == SymKind::Macro )
    {
        body = fieldChild( roleNode, NodeField::Value );
    }
    return body;
}

// DART's body is a SIBLING, not a field and not a child. tree-sitter-dart emits `function_body` next to
// `function_signature` / `method_signature`, so defBodyNodeOf finds nothing, the shared ancestor climb in
// captureTagsFacts finds nothing either, and the definition's span stops at the signature's closing paren —
// after which every call in the body attributes to the nearest ENCLOSING symbol. Measured on test/dartfix
// before this existed: `square` landed on the class `Calculator` rather than the method `accumulate`, and
// the three top-level edges were lost outright, 5 edges where 8 are expected. Scanning FORWARD to the next
// NAMED sibling is what keeps an abstract member honest: `void f();` has no function_body, the scan stops at
// the next declaration, the body stays null and the symbol stays a declaration. Same reason as
// defBodyNodeOf's: one call at the dispatch point instead of a loop inside it. Gate: test/dartcheck.sh.
TSNode dartFollowingBody( TSNode defNode ) noexcept
{
    for( TSNode sib = ts_node_next_sibling( defNode ); !ts_node_is_null( sib ); sib = ts_node_next_sibling( sib ) )
    {
        if( kindIs( ts_node_type( sib ), "function_body" ) )
        {
            return sib;
        }
        if( ts_node_is_named( sib ) )
        {
            break;   // the signature/body pair ended
        }
    }
    return {};
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
    if( !kindIs( ts_node_type( defineNode ), "preproc_function_def" ) )
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
    if( const TSNode nameNode = fieldChild( defineNode, NodeField::Name ); !ts_node_is_null( nameNode ) )
    {
        const uint32_t na = ts_node_start_byte( nameNode );
        const uint32_t nb = ts_node_end_byte( nameNode );
        if( na < nb && nb <= src.size() )
        {
            macroName.assign( src.substr( na, nb - na ) );
        }
    }
    std::vector<std::string> params;
    if( const TSNode paramsNode = fieldChild( defineNode, NodeField::Parameters ); !ts_node_is_null( paramsNode ) )
    {
        // O(children): a preproc_params list holds every block comment written between its names — extras
        // land in the child array (src/infra/tschildren.h); 16 000 of them measured 60x the identical flood
        // outside the #define (test/childwalkscalecheck.sh, arm B13).
        ChildCursor cursor( paramsNode );
        forEachChild( paramsNode, cursor.cur, [ & ]( TSNode ch )
        {
            if( kindIs( ts_node_type( ch ), "identifier" ) )
            {
                const uint32_t pa = ts_node_start_byte( ch );
                const uint32_t pb = ts_node_end_byte( ch );
                if( pa < pb && pb <= src.size() )
                {
                    params.emplace_back( src.substr( pa, pb - pa ) );
                }
            }
            return true;
        } );
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
// C#/PHP/Kotlin. Lua is deliberately absent and it is a DISCLOSED non-goal, not an omission: Lua inheritance IS
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
//               Kotlin delegation_specifier → constructor_invocation → user_type (`class Foo : Bar(args)`);
//               a bare interface (`class Foo : Baz`, no call) hits DIRECT instead — user_type sits right
//               under delegation_specifier with no constructor_invocation wrapper.
// So after matching a clause we scan its children for type nodes AND recurse one level into any wrapper
// child, collecting type nodes at both depths (Rust is a separate pass — impl Trait for T is a sibling).
void captureBases( TSNode classNode, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawRef>& refs )
{
    // O(children) at all three levels. These child lists LOOK grammar-bounded — a class node's clauses, a
    // clause's base types — and the earlier class-3 reasoning said so, but EXTRAS refute it: a comment run
    // between two base types is spliced straight into the clause's own child array (src/infra/tschildren.h),
    // and 16 000 of them measured 118× the same file with the flood outside the clause
    // (test/childwalkscalecheck.sh, arm B10). Each level owns its cursor — the loops nest.
    ChildCursor classCursor( classNode );
    forEachChild( classNode, classCursor.cur, [ & ]( TSNode clause )
    {
        const char* ct = ts_node_type( clause );
        const bool   isClause =    kindIs( ct, "base_class_clause" )     // C++    : public Base
                                || kindIs( ct, "class_heritage" )        // TS/JS  extends / implements (wraps clauses)
                                || kindIs( ct, "superclasses" )          // Python class X(Base):   (field)
                                || kindIs( ct, "argument_list" )         // Python bases
                                || kindIs( ct, "superclass" )            // Java   extends Base
                                || kindIs( ct, "super_interfaces" )      // Java   implements I, J   (wraps type_list)
                                || kindIs( ct, "inheritance_specifier" ) // Swift  : Protocol
                                || kindIs( ct, "base_list" )             // C#     : Base, IBar
                                || kindIs( ct, "base_clause" )           // PHP    extends Base
                                || kindIs( ct, "class_interface_clause" ) // PHP  implements I, J
                                || kindIs( ct, "delegation_specifier" ); // Kotlin : Base(), Interface (one per base)
        if( !isClause )
        {
            return true;
        }

        ChildCursor clauseCursor( clause );
        forEachChild( clause, clauseCursor.cur, [ & ]( TSNode bn )
        {
            const char* bt = ts_node_type( bn );
            if( isBaseTypeNode( bt ) )                 // DIRECT: type node right under the clause
            {
                emitBaseRef( bn, fileId, lang, src, refs );
                return true;
            }
            // WRAPPED: descend ONE level into a wrapper (extends_clause / implements_clause / type_list)
            // and emit each type node it holds. One level is enough for every measured grammar shape.
            ChildCursor wrapCursor( bn );
            forEachChild( bn, wrapCursor.cur, [ & ]( TSNode wn )
            {
                if( isBaseTypeNode( ts_node_type( wn ) ) )
                {
                    emitBaseRef( wn, fileId, lang, src, refs );
                }
                return true;
            } );
            return true;
        } );
        return true;
    } );
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
    if( !kindIs( t, "impl_item" ) )
    {
        return;
    }
    const TSNode traitNode = fieldChild( node, NodeField::Trait );
    const TSNode typeNode  = fieldChild( node, NodeField::Type );
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
        if( !kindIs( ct, "field_declaration_list" ) )
        {
            continue;
        }

        collectChildren( child, cursor.cur, fieldKids );
        for( const TSNode fdecl : fieldKids )
        {
            if( !kindIs( ts_node_type( fdecl ), "field_declaration" ) )
            {
                continue;
            }

            // The "type" field of a field_declaration. We look for:
            //   type_identifier — a plain class name (SpherePool)
            //   type_descriptor — a reference/pointer type containing a type_identifier
            // We consider type_identifier directly under type= as the declared type.
            const TSNode typeNode = fieldChild( fdecl, NodeField::Type );
            if( ts_node_is_null( typeNode ) )
            {
                continue;
            }

            const char* tnType = ts_node_type( typeNode );

            // Determine the type name and whether this is a reference/pointer (uses) or value (creates).
            std::string typeName;
            bool isRefOrPtr = false;   // reference (&) or pointer (*) → "uses"; else "creates"

            if( kindIs( tnType, "type_identifier" ) )
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
            else if(    kindIs( tnType, "reference_declarator" )
                     || kindIs( tnType, "pointer_declarator" ) )
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
                // O(children): a qualified_identifier `ns /*…*/ ::T` owns every comment between its tokens —
                // 16 000 of them measured 16x the identical flood after the field (childwalkscalecheck B14).
                // `cursor` is free here: the enclosing loops walk materialised vectors, not the cursor.
                bool found = false;
                forEachChild( typeNode, cursor.cur, [ & ]( TSNode tc3 )
                {
                    if( kindIs( ts_node_type( tc3 ), "type_identifier" ) )
                    {
                        const uint32_t ta = ts_node_start_byte( tc3 ), tb = ts_node_end_byte( tc3 );
                        if( ta < tb && tb <= src.size() ) { typeName = std::string( src.substr( ta, tb - ta ) ); found = true; }
                    }
                    return !found;
                } );
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
            const TSNode decl = fieldChild( fdecl, NodeField::Declarator );
            if( ts_node_is_null( decl ) )
            {
                continue;
            }

            const char* dt = ts_node_type( decl );

            std::string fieldName;
            bool        declIsRefOrPtr = false;

            if( kindIs( dt, "field_identifier" ) )
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
            else if( kindIs( dt, "reference_declarator" ) || kindIs( dt, "pointer_declarator" ) )
            {
                declIsRefOrPtr = true;
                // Walk the declarator's children to find the field_identifier — O(children): `T & /*…*/ m` puts
                // the comments in the reference_declarator (14x at 16 000, childwalkscalecheck B15)
                forEachChild( decl, cursor.cur, [ & ]( TSNode dchild )
                {
                    if( kindIs( ts_node_type( dchild ), "field_identifier" ) )
                    {
                        const uint32_t da = ts_node_start_byte( dchild ), db = ts_node_end_byte( dchild );
                        if( da < db && db <= src.size() ) { fieldName = std::string( src.substr( da, db - da ) ); return false; }
                    }
                    return true;
                } );
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
    if( kindIs( ts_node_type( node ), "string" ) && s.size() >= 2 && ( s.front() == '\'' || s.front() == '"' ) && s.back() == s.front() )
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
    if( const TSNode aliasType = fieldChild( usingNode, NodeField::Type ); !ts_node_is_null( aliasType ) )
    {
        return importSpecifierText( aliasType, src );
    }

    // O(children): `using /*…*/ System.Text;` puts the comments in the using_directive itself — 16 000 of
    // them measured 36x the identical flood inside a method body (test/childwalkscalecheck.sh, arm B16)
    const TSNode c = firstChildOfKind( usingNode, /*namedOnly=*/true, { "qualified_name", "identifier", "generic_name", "alias_qualified_name" } );
    return ts_node_is_null( c ) ? std::string {} : importSpecifierText( c, src );
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
    // O(children) at both levels: `use /*…*/ Foo\Bar;` floods the namespace_use_declaration (54x at 16 000,
    // test/childwalkscalecheck.sh arm B17), and the same comments inside a `{A, B}` group would flood the
    // clause. Two cursors, because the clause walk runs while the declaration walk is mid-iteration.
    std::string target;
    ChildCursor clauses( useNode );
    ChildCursor names( useNode );
    forEachNamedChild( useNode, clauses.cur, [ & ]( TSNode c )
    {
        const char* ct = ts_node_type( c );
        if( kindIs( ct, "namespace_name" ) )      // the `use Foo\{A, B}` group prefix
        {
            target = importSpecifierText( c, src );
            return false;
        }
        if( !kindIs( ct, "namespace_use_clause" ) )
        {
            return true;
        }
        bool hit = false;
        forEachNamedChild( c, names.cur, [ & ]( TSNode g )
        {
            const char* gt = ts_node_type( g );
            if( kindIs( gt, "qualified_name" ) || kindIs( gt, "name" ) )
            {
                target = importSpecifierText( g, src );
                hit    = true;
                return false;
            }
            return true;
        } );
        return !hit;
    } );
    return target;
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
    const std::string_view callee = nodeFieldText( n, NodeField::Function, src );
    if( callee != "require" && callee != "import" )
    {
        return {};
    }
    const TSNode ar = fieldChild( n, NodeField::Arguments );
    if( ts_node_is_null( ar ) )
    {
        return {};
    }

    TSNode      only  = { };
    uint32_t    named = 0;
    ChildCursor cursor( ar );   // O(children): `require( /*…*/ 'x' )` — 54x at 16 000 (childwalkscalecheck B18)
    forEachNamedChild( ar, cursor.cur, [ & ]( TSNode c ) { only = c; ++named; return true; } );
    if( named != 1 || !kindIs( ts_node_type( only ), "string" ) )
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
    // No empty-guard: includePathOf( "" ) already returns "" through its own size < 2 arm, and leaves
    // isAngleOut alone doing it. The guard that used to stand here was dead, and --quality-delta found it
    // the way dead code is usually found — as a duplication, once the two call sites normalised alike.
    return includePathOf( nodeFieldText( n, NodeField::Path, src ), isAngleOut );
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
    if( nodeFieldText( n, NodeField::Directive, src ) != "#import" )
    {
        return {};
    }
    // preproc_arg runs to end-of-line, so the CLOSING delimiter ends the path — includePathOf's job.
    return includePathOf( nodeFieldText( n, NodeField::Argument, src ), isAngleOut );
}

// ─── kParserVer 81: the four languages that had no directive branch at all ───────────────────────────
//
// Bash / Lua / Ruby / Elixir each spell a real FILE dependency, and each of the four spells it as an
// ordinary CALL rather than a reserved statement — which is why `directiveTargetOf` had no branch for
// them and why lintrules.h's dependencyCapable() called all four false. That was a fact about this
// extractor, never about the languages: `source lib.sh`, `require "a.b"`, `require_relative "x"` and
// `alias MyApp.Foo` all name a file the way `#include "x.h"` does. The call-shaped spelling is the whole
// difficulty, because `call_expression`/`function_call`/`call`/`command` are node types EVERY grammar
// has: the language gate plus a literal-name check is what keeps a C++ function called `require`, or a
// Ruby method a user named `load`, from manufacturing a dependency edge — the same guard, for the same
// reason, that jsModuleLoadTarget already carries for CommonJS.
//
// Every one of the four reads its argument through the grammar's own STRING node and takes the
// `string_content` child, never a byte slice: an interpolated specifier (`require "#{x}"`,
// `source "$dir/$f"`) then has no single literal to read, and the honest outcome is no target at all
// rather than a guess assembled out of the parts.

// Defined in ingest_elixir.h, which ingest.cpp includes AFTER this file — declared, not copied: an
// Elixir call's `arguments` child is one shape and it already has one reader, and a second private copy
// here is exactly the duplication --quality-delta flags. Same TU, same anonymous namespace.
TSNode elixirArguments( TSNode node ) noexcept;

// The literal text a shell word/string argument names, or empty when the argument is not a literal at
// all. `word` is an unquoted argument (`source ./lib.sh`), `string`/`raw_string` a quoted one; a
// `concatenation` (unquoted `$ROOT/x.sh`) is returned VERBATIM, expansions included, because the
// resolver — not this extractor — is what decides whether an expansion leaves a resolvable literal tail
// (resolve.h::resolveBashSource). Returning it verbatim is also what puts the un-expandable specifier in
// `--deps`'s own `<inc t="$1">` row: a directive we cannot resolve is DISCLOSED at the site, exactly the
// way an unresolvable `#include <vector>` is, instead of vanishing.
inline std::string bashWordText( TSNode arg, std::string_view src )
{
    if( ts_node_is_null( arg ) )
    {
        return {};
    }
    const char* t = ts_node_type( arg );
    if( kindIs( t, "word" ) || kindIs( t, "concatenation" ) )
    {
        return std::string( nodeTextOf( arg, src ) );
    }
    if( kindIs( t, "string" ) || kindIs( t, "raw_string" ) )
    {
        std::string_view s = nodeTextOf( arg, src );
        if( s.size() >= 2 && ( s.front() == '"' || s.front() == '\'' ) && s.back() == s.front() )
        {
            s = s.substr( 1, s.size() - 2 );   // strip exactly one delimiter pair, as importSpecifierText does
        }
        return std::string( s );
    }
    return {};   // an expansion/substitution ALONE (`source $f`) carries no literal — no target
}

// Bash `source FILE` / `. FILE` — a `command` node whose name is one of the two spellings of the ONE
// builtin that reads another file into this shell. There is no name→path convention to model here at
// all: the argument IS the path, which makes Bash the only one of the four whose specifier needs no
// dialect rule, and the only one whose specifier is routinely a VARIABLE (`. "$ROOT/scripts/x.sh"` — 29
// of the 29 source lines in this repo's own test/ are that shape, so the expansion case is the common
// case here, not the corner). Only the FIRST argument is read: `source lib.sh a b` passes a and b as
// positional parameters to the sourced script, they are not further files.
inline std::string bashSourceTarget( TSNode n, std::string_view src )
{
    const std::string_view name = nodeFieldText( n, NodeField::Name, src );
    if( name != "source" && name != "." )
    {
        return {};
    }
    return bashWordText( fieldChild( n, NodeField::Argument ), src );
}

// The first STRING-literal argument of a call-shaped node, read through the grammar: `arguments`/
// `argument_list` → first named child must be a `string`, and its text comes from the `string_content`
// child so an interpolated or concatenated specifier yields nothing rather than a fragment. Shared by
// Lua and Ruby, whose argument nodes differ only in name.
inline std::string stringLiteralText( TSNode str, std::string_view src )
{
    if( ts_node_is_null( str ) || !kindIs( ts_node_type( str ), "string" ) )
    {
        return {};   // `require(mod)`, `require("a" .. b)`, `require "#{x}"` — no single literal to read
    }
    // Indexed on purpose: a string's children come from the external scanner, which owns every byte between
    // the delimiters, so no comment token is ever lexed into this list (src/infra/tschildren.h's one-line test).
    for( std::uint32_t i = 0; i < ts_node_named_child_count( str ); ++i )
    {
        const TSNode kid = ts_node_named_child( str, i );
        if( kindIs( ts_node_type( kid ), "string_content" ) )
        {
            return std::string( nodeTextOf( kid, src ) );
        }
    }
    return {};   // an empty string literal, or one whose only children are interpolations
}
inline std::string firstStringArgText( TSNode args, std::string_view src )
{
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) == 0 )
    {
        return {};
    }
    return stringLiteralText( ts_node_named_child( args, 0 ), src );
}

// Lua `require "a.b"` / `require("a.b")` — a `function_call` whose `name:` is the bare identifier
// `require`. The dotted specifier is package.path's convention, resolved in resolve.h::resolveLuaRequire
// (`a.b` → `a/b.lua`). `name:` must be an `identifier`, never a `dot_index_expression`: `pkg.require("x")`
// is somebody's own method, not the loader.
inline std::string luaRequireTarget( TSNode n, std::string_view src )
{
    const TSNode name = fieldChild( n, NodeField::Name );
    if( ts_node_is_null( name ) || !kindIs( ts_node_type( name ), "identifier" ) || nodeTextOf( name, src ) != "require" )
    {
        return {};
    }
    return firstStringArgText( fieldChild( n, NodeField::Arguments ), src );
}

// Ruby `require_relative "x"` / `require "lib/x"` / `load "x.rb"` — a `call` whose `method:` is one of
// the three Kernel loaders and which has NO receiver (`foo.require` is somebody's own method; the bare
// spelling is the only one that is provably Kernel's). `autoload :Foo, "lib/x"` was a disclosed floor here
// through kParserVer 81 (its path is argument TWO); rubyAutoloadTarget below lifts it, and the constant
// spellings — superclass, include/extend/prepend, path-less `autoload :Foo` — live in rubyConstantDirective
// and rubyMixinTargets, resolved by index rather than by path (Include::isSymbolic).
//
// The two resolution rules are encoded in the target the way Python's already are — by a LEADING DOT,
// not by a new prefix vocabulary. `require_relative`'s path is relative to the requiring FILE, so a
// specifier that does not already start with `.` gets `./` prepended (`lib/helper` → `./lib/helper`);
// `require`'s is searched on $LOAD_PATH, so it stays bare and resolve.h probes the load-path roots.
// `require "./x"` keeps its dot and is therefore read file-relative — an approximation (Ruby resolves
// it against the process CWD, which is not knowable here), and one that can only ever RESOLVE, never
// mis-resolve: unique-or-degrade means a wrong file-relative guess simply finds nothing.
inline std::string rubyRequireTarget( TSNode n, std::string_view src )
{
    if( !ts_node_is_null( fieldChild( n, NodeField::Receiver ) ) )
    {
        return {};
    }
    const TSNode method = fieldChild( n, NodeField::Method );
    if( ts_node_is_null( method ) || !kindIs( ts_node_type( method ), "identifier" ) )
    {
        return {};
    }
    const std::string_view m = nodeTextOf( method, src );
    if( m != "require" && m != "require_relative" && m != "load" )
    {
        return {};
    }
    std::string spec = firstStringArgText( fieldChild( n, NodeField::Arguments ), src );
    if( spec.empty() )
    {
        return {};
    }
    if( m == "require_relative" && spec.front() != '.' )
    {
        spec.insert( 0, "./" );
    }
    return spec;
}

// Ruby constant spellings (parser version 82). A Rails application spells almost none of its dependencies with
// `require`: a controller depends on a model by NAMING THE CONSTANT, and a gem declares its structure with
// `autoload :Name`. Measured on a Rails app of 3532 .rb files before this round (`--deps`, the uncapped
// <godfiles total=>): 103 files in the whole tree had an incoming dependency edge; after it, 385. The three
// readers below emit the constant AS WRITTEN (`Base`, `::App::User`,
// `ActiveRecord::Base`) with Include::isSymbolic set, so resolve.h resolves it by Ruby's own lexical rule
// against the corpus's class/module index and never probes it as a path (test/rubyconstcheck.sh).

// Ruby (parser version 82): does this `class`/`module` open DEFINE anything of its own constant, or is it a
// NAMESPACE WRAPPER — `module App … end` whose body holds nothing but nested class/module definitions?
// A wrapper adds nothing to `App`; the file that gives App a body (`VERSION = …`, `extend Autoload`,
// `def self.x`, `class << self`) is its definer. Structural, never a count: measured on a 3532-file Rails
// app, 124 constants were "defined in many files" by opens and 5 by bodies, and treating the wrappers as
// definers is exactly what made 246 superclass references ambiguous there. Comments are grammar extras and
// appear as named children, so they are skipped. An EMPTY open (`class Base; end`, `class NotFound <
// StandardError; end`, a marker module) is NOT a wrapper: it holds no nested open to be a namespace FOR,
// and it is how Ruby spells a constant whose whole definition is its existence — so it defines. Recorded on the ConstOpen captureIncludes emits; read by resolve.h::buildRubyConstantIndex (test/rubyconstcheck.sh, namespace arms).
inline bool rubyNamespaceOnly( TSNode defNode ) noexcept
{
    const TSNode body = fieldChild( defNode, NodeField::Body );
    if( ts_node_is_null( body ) )
    {
        return false;   // an empty open defines its constant
    }
    // O(children): the scan already skips `comment` by kind, which is the author knowing they land in this
    // list — 16 000 of them measured 58x the identical flood after the class (childwalkscalecheck B19)
    bool        nestedOpen = false;
    bool        ownBody    = false;
    ChildCursor cursor( body );
    forEachNamedChild( body, cursor.cur, [ & ]( TSNode c )
    {
        const char* ct = ts_node_type( c );
        if( kindIs( ct, "class" ) || kindIs( ct, "module" ) )
        {
            nestedOpen = true;
        }
        else if( !kindIs( ct, "comment" ) )
        {
            ownBody = true;   // a method, a call, a constant, `class << self` — a body of its own
            return false;
        }
        return true;
    } );
    return !ownBody && nestedOpen;
}

// The text of a constant-shaped node — `constant` (`Base`) or `scope_resolution` (`A::B`, `::Top`) — or
// empty for anything else (`include Object.const_get(:X)`, `class Foo < some_call` are not readable).
inline std::string rubyConstantText( TSNode n, std::string_view src )
{
    if( ts_node_is_null( n ) )
    {
        return {};
    }
    const char* t = ts_node_type( n );
    if( !kindIs( t, "constant" ) && !kindIs( t, "scope_resolution" ) )
    {
        return {};
    }
    return std::string( nodeTextOf( n, src ) );
}

// `class X < Base` — the `superclass` node's one named child is the base constant.
inline std::string rubySuperclassTarget( TSNode superclassNode, std::string_view src )
{
    const std::uint32_t n = ts_node_named_child_count( superclassNode );
    return n == 0 ? std::string{} : rubyConstantText( ts_node_named_child( superclassNode, 0 ), src );
}

// `autoload :Name` / `autoload :Name, "path"` — a receiver-less `call` whose method is `autoload` and whose
// first argument is a `simple_symbol`. TWO forms, ONE directive each, never both:
//   * with a string second argument (Kernel#autoload) the PATH is what Ruby loads — returned bare, so the
//     load-path rule resolves it exactly like a `require`; `symbolic` is false.
//   * with no second argument (ActiveSupport::Autoload, whose path is derived from the enclosing module) the
//     CONSTANT is the target; `symbolic` is true. The index resolves it whatever `autoload_under`/
//     `autoload_at` did to the path — a path rule would have had to model both.
//   * a second argument that is not a string literal (`autoload :X, some_path`) is nothing: the path is
//     unknowable and the constant alone would guess at what the path was meant to say.
// Both forms are LAZY by definition (Include::isLazy): the file loads on the constant's first use.
inline std::string rubyAutoloadTarget( TSNode n, std::string_view src, bool& symbolic )
{
    symbolic = false;
    const TSNode args = fieldChild( n, NodeField::Arguments );
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) == 0 )
    {
        return {};
    }
    const TSNode sym = ts_node_named_child( args, 0 );
    if( !kindIs( ts_node_type( sym ), "simple_symbol" ) )
    {
        return {};
    }
    if( ts_node_named_child_count( args ) >= 2 )
    {
        return stringLiteralText( ts_node_named_child( args, 1 ), src );   // empty when not a literal → nothing
    }
    std::string_view txt = nodeTextOf( sym, src );
    if( !txt.empty() && txt.front() == ':' )
    {
        txt.remove_prefix( 1 );
    }
    if( txt.empty() || !( txt.front() >= 'A' && txt.front() <= 'Z' ) )
    {
        return {};   // `autoload :"weird"` / a lowercase symbol is not a constant
    }
    symbolic = true;
    return std::string( txt );
}

// The receiver-less `call` node's method name when it is one of the constant-shaped directives, else empty.
// `autoload` and the three mixin verbs; `obj.include X` is somebody's own method and reads as nothing.
inline std::string_view rubyConstantDirective( TSNode n, std::string_view src )
{
    if( !ts_node_is_null( fieldChild( n, NodeField::Receiver ) ) )
    {
        return {};
    }
    const TSNode method = fieldChild( n, NodeField::Method );
    if( ts_node_is_null( method ) || !kindIs( ts_node_type( method ), "identifier" ) )
    {
        return {};
    }
    const std::string_view m = nodeTextOf( method, src );
    if( m == "include" || m == "extend" || m == "prepend" || m == "autoload" )
    {
        return m;
    }
    return {};
}

// `include A, B` / `extend M` / `prepend P` — ONE directive naming N constants and therefore N Include
// records, in SOURCE order (the same shape as elixirAliasGroup). A non-constant argument (`include
// Object.const_get(:X)`, `include mod`) contributes nothing; the constant ones beside it still do.
inline std::vector<std::string> rubyMixinTargets( TSNode n, std::string_view src )
{
    std::vector<std::string> out;
    const std::string_view   m = rubyConstantDirective( n, src );
    if( m.empty() || m == "autoload" )
    {
        return out;
    }
    const TSNode args = fieldChild( n, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        return out;
    }
    ChildCursor cursor( args );   // O(children): `include A, # … B` — 58x at 16 000 (childwalkscalecheck B20)
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        if( std::string c = rubyConstantText( a, src ); !c.empty() )
        {
            out.push_back( std::move( c ) );
        }
        return true;
    } );
    return out;
}

// A CONSTANT CHAIN: `Name`, `A::B::C`, `::A::B` — every segment a constant, the head a constant or absent (`::A`).
// rubyConstantText above accepts any scope_resolution and is right for the positions Ruby's grammar already
// restricts to constants (a class name, a superclass, a mixin argument); a RECEIVER is not such a position —
// `repo::Finder.call` and `self.class::Foo.bar` are scope_resolutions whose head is an identifier or a call,
// and naming them as constants would invent a dependency on nothing. Empty when any segment is not a constant.
//
// A LOOP, not a recursion (parser version 86). `A::B::C` parses left-nested — scope_resolution(scope:
// scope_resolution(scope: A, name: B), name: C) — so the chain's depth is its segment count, and a recursive
// check spent one native frame per segment: a 5000-segment receiver overflowed a parse worker's stack (SIGBUS,
// measured on macOS) and took the whole run with it, before the depth-bounded walk in captureIncludes ever saw
// the node. The gate builds a 150 000-segment chain and expects one directive.
inline bool rubyIsConstantChain( TSNode n ) noexcept
{
    for( ;; )
    {
        if( ts_node_is_null( n ) )
        {
            return false;
        }
        const char* t = ts_node_type( n );
        if( kindIs( t, "constant" ) )
        {
            return true;
        }
        if( !kindIs( t, "scope_resolution" ) )
        {
            return false;
        }
        const TSNode name  = fieldChild( n, NodeField::Name );
        const TSNode scope = fieldChild( n, NodeField::Scope );
        if( ts_node_is_null( name ) || !kindIs( ts_node_type( name ), "constant" ) )
        {
            return false;
        }
        if( ts_node_is_null( scope ) )
        {
            return true;   // null scope = the absolute `::A` form: the chain's head
        }
        n = scope;   // one segment inward; the loop is the recursion, minus the frame
    }
}

// Parser version 83 (test/rubyrecvcheck.sh): a CONSTANT RECEIVER — `User.find`, `App::Mailer.deliver`,
// `Struct.new` — is the Zeitwerk dependency proper: the autoloader loads the constant's file on that first
// reference. The target is the receiver chain AS WRITTEN (`::Time` and `Time` are two spellings, two
// directives); a receiver that is not a constant chain — an identifier, `self.class`, an ivar, `repo::Finder`
// — yields nothing. A constant used as an ARGUMENT (`raise Errors::Boom`, `validates_with Foo`) or as a
// rescue class is NOT a receiver: a disclosed floor of this round, stated in the gate's header.
inline std::string rubyReceiverTarget( TSNode n, std::string_view src )
{
    const TSNode recv = fieldChild( n, NodeField::Receiver );
    if( !rubyIsConstantChain( recv ) )
    {
        return {};
    }
    return std::string( nodeTextOf( recv, src ) );
}

// Elixir `alias`/`import`/`require`/`use` — a `call` whose `target:` is one of the four directive
// identifiers. All four are compile-time dependencies on the named module's FILE (`use` most of all: it
// runs that module's `__using__` macro at compile time), so all four earn an edge.
//
// Two argument shapes, both read off a real parse: `alias MyApp.Foo` puts a single `(alias)` first in
// `arguments`; `alias MyApp.{Bar, Baz}` puts a `(dot left: (alias) right: (tuple (alias)…))` there,
// which is ONE directive naming N modules and therefore N Include records — see elixirAliasGroup below.
// A trailing `, as: F` / `, only: […]` is a later `arguments` child and is ignored here.
//
// NOT HANDLED, and disclosed rather than approximated: `alias A.B.C` also binds the NAME `C` in this
// module, so a later `C.f()` means `A.B.C.f`. That is a call-RESOLUTION fact, not a file-dependency one,
// and it needs the receiver of the call — which queries/elixir/tags.scm deliberately does not keep
// (`(dot right: (identifier) @name) @reference.call` captures `run`, not `Foo.run`). The file edge lands;
// the name alias does NOT narrow call resolution, exactly as that query's own comment already says.
inline std::string elixirDirectiveTarget( TSNode n, std::string_view src )
{
    const TSNode target = fieldChild( n, NodeField::Target );
    if( ts_node_is_null( target ) || !kindIs( ts_node_type( target ), "identifier" ) )
    {
        return {};
    }
    const std::string_view kw = nodeTextOf( target, src );
    if( kw != "alias" && kw != "import" && kw != "require" && kw != "use" )
    {
        return {};
    }
    const TSNode args = elixirArguments( n );
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) == 0 )
    {
        return {};
    }
    const TSNode first = ts_node_named_child( args, 0 );
    if( ts_node_is_null( first ) || !kindIs( ts_node_type( first ), "alias" ) )
    {
        return {};   // a `dot` brace group is emitted by elixirAliasGroup; anything else is not a module name
    }
    return std::string( nodeTextOf( first, src ) );
}

// `alias MyApp.{Bar, Baz}` → the member module names, fully qualified. Empty for every other shape,
// including the single-alias form (which elixirDirectiveTarget already owns) — the two are exclusive by
// construction, so one directive can never emit both a target and a group.
inline std::vector<std::string> elixirAliasGroup( TSNode n, std::string_view src )
{
    std::vector<std::string> out;
    const TSNode target = fieldChild( n, NodeField::Target );
    if( ts_node_is_null( target ) || !kindIs( ts_node_type( target ), "identifier" ) )
    {
        return out;
    }
    const std::string_view kw = nodeTextOf( target, src );
    if( kw != "alias" && kw != "import" && kw != "require" && kw != "use" )
    {
        return out;
    }
    const TSNode args = elixirArguments( n );
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) == 0 )
    {
        return out;
    }
    const TSNode first = ts_node_named_child( args, 0 );
    if( ts_node_is_null( first ) || !kindIs( ts_node_type( first ), "dot" ) )
    {
        return out;
    }
    const TSNode left  = fieldChild( first, NodeField::Left );
    const TSNode right = fieldChild( first, NodeField::Right );
    if( ts_node_is_null( left ) || ts_node_is_null( right )
        || !kindIs( ts_node_type( left ), "alias" ) || !kindIs( ts_node_type( right ), "tuple" ) )
    {
        return out;
    }
    const std::string_view prefix = nodeTextOf( left, src );
    ChildCursor            cursor( right );   // O(children): `{A, # … B}` — 86x at 16 000 (childwalkscalecheck B21)
    forEachNamedChild( right, cursor.cur, [ & ]( TSNode member )
    {
        if( kindIs( ts_node_type( member ), "alias" ) )
        {
            const std::string_view name = nodeTextOf( member, src );
            if( !prefix.empty() && !name.empty() )
            {
                out.emplace_back( std::string( prefix ) + "." + std::string( name ) );
            }
        }
        return true;
    } );
    return out;
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

// kParserVer 81 — the four new languages' container sets. EVERY entry below was read off a real parse
// with `--match='(<node>) @c'`, never predicted from a grammar file; a node type that does not exist
// makes that query REFUSE to compile, which is how the absent ones (bash has no `until_statement`, lua no
// `local_declaration`) were found and dropped rather than left in as noise.
//
// BASH. A `source` is an ordinary command, so every construct that can hold a command is a container.
// The chains that matter and are NOT reachable without the intermediate: a function body is
// `function_definition -> compound_statement -> command`; a loop body is `for_statement -> do_group ->
// command`; a case arm is `case_statement -> case_item -> command`; and `[ -f x ] && source y` is a
// `list`. `redirected_statement` covers `. lib.sh >/dev/null`, `command_substitution` a `$( . x )`.
inline constexpr std::array<std::string_view, 17> kBashImportContainers = {
    "compound_statement", "subshell", "do_group",                                  // the three body kinds
    "function_definition", "for_statement", "c_style_for_statement", "while_statement",
    "if_statement", "elif_clause", "else_clause",
    "case_statement", "case_item",
    "list", "pipeline", "negated_command", "redirected_statement", "command_substitution"
};

// LUA. `local m = require "x"` is `variable_declaration -> assignment_statement -> expression_list ->
// function_call`, so all three intermediates are load-bearing; `function_declaration`/`block` reach a
// body; `table_constructor`/`field` reach `M.dep = require "x"` inside a returned table, which is how a
// module's dependency list is idiomatically written.
inline constexpr std::array<std::string_view, 16> kLuaImportContainers = {
    "block", "function_declaration", "function_definition",
    "variable_declaration", "assignment_statement", "expression_list", "return_statement",
    "if_statement", "elseif_statement", "else_statement",
    "while_statement", "repeat_statement", "for_statement", "do_statement",
    "table_constructor", "field"
};

// RUBY has NO container allowlist: the walk descends EVERY node (isImportContainer below). Through parser
// version 82 it had one — the statement-level shapes a `require`/`autoload`/`include`/`class X < Base` can sit
// under. Parser version 83 made a constant RECEIVER a directive, and a receiver is an EXPRESSION: it sits
// under an assignment (`DEFAULT = Helper.fmt(1)`), an argument list (`puts User.name`), a lambda, a binary,
// a conditional, a string interpolation — the whole expression grammar. An allowlist there would be ~40
// kinds long and every kind it missed would be a receiver silently dropped, a floor this tool could not
// disclose because it could not see it. The full descent is the same cost the reference pass already pays
// once per Ruby file (one visit per node, one directive test each) and reaches every receiver by
// construction. The depth bound still holds (kMaxImportContainerDepth); a Ruby tree past it degrades loudly.
// The CLOSURE kinds — where a receiver runs only when and if the closure runs — are kRubyClosureContainers.

// ELIXIR. `defmodule M do … end` is itself a `call` with a `do_block`, so `call` MUST be a container or
// no directive in any module body is ever visited — this is the one language here whose top-level form
// is a container. `stab_clause` is a `case`/`cond`/`fn` arm; `body` is a `stab_clause`'s own body.
// `arguments`/`keywords` reach the keyword-list body form (`if x, do: alias Y`).
// DISCLOSED over-capture: a `quote do … end` is also a `call` with a `do_block`, so an `alias` inside
// quoted AST is captured. That is the same union-over-arms posture the preprocessor tables take — a
// spurious edge, never a missing one — and it disagrees with queries/elixir/tags.scm's symbol side,
// which omits quoted AST. Excluding it would need the walk to read node TEXT to identify `quote`, which
// isImportContainer (a node-KIND predicate shared by every grammar) deliberately cannot do.
inline constexpr std::array<std::string_view, 6> kElixirImportContainers = {
    "call", "do_block", "stab_clause", "body", "arguments", "keywords"
};

// KOTLIN. Unlike every other language in this table, an `import` is not a general statement that CAN
// appear inside a function/class body — the language itself only allows it at file top level, before
// any other declaration. Empirically confirmed (not assumed from the grammar): every import_header in
// two real corpora (Nanidroid, the socialite sample app), across single- and multi-import files, has
// the SAME two-deep parent chain with no variation — `import_list -> source_file`. One entry.
inline constexpr std::array<std::string_view, 1> kKotlinImportContainers = { "import_list" };

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

// RUBY's closure kinds (parser version 83, test/rubyrecvcheck.sh): a constant receiver written inside any of these
// runs when and if the closure runs — a method body, a singleton method, a `-> { }` lambda, a `{ }` block, a
// `do … end` block — so the directive is LAZY (Include::isLazy), exactly the parser-72 TS/JS rule on Ruby's
// own closure grammar. A receiver at class-body or file level runs at load and is not lazy. A `do`-block passed
// to a class-level macro (`included do`, `after_commit do`) is lazy under this rule even when the callee runs it
// at load: the tool cannot see the callee, and a block is a closure the callee may or may not run.
inline constexpr std::array<std::string_view, 5> kRubyClosureContainers = {
    "method", "singleton_method", "lambda", "block", "do_block"
};

inline bool isFunctionLike( Lang lang, const char* type ) noexcept
{
    if( lang == Lang::TypeScript || lang == Lang::JavaScript )
    {
        return namesNode( kJsFunctionContainers, type );
    }
    if( lang == Lang::Ruby )
    {
        return namesNode( kRubyClosureContainers, type );
    }
    return false;
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

inline constexpr std::array<LangImportContainers, 9> kImportContainersByLang = { {
    { Lang::Python,     kPythonImportContainers },
    { Lang::Rust,       kRustImportContainers   },
    { Lang::CSharp,     kCsharpImportContainers },
    { Lang::TypeScript, kJsImportContainers     },
    { Lang::JavaScript, kJsImportContainers     },
    { Lang::Bash,       kBashImportContainers   },
    { Lang::Lua,        kLuaImportContainers    },
    { Lang::Elixir,     kElixirImportContainers },
    { Lang::Kotlin,     kKotlinImportContainers }
} };

inline bool isImportContainer( Lang lang, const char* type ) noexcept
{
    if( isPreprocConditional( type ) )   // every grammar with a preprocessor: C/C++/ObjC/CUDA/Metal + C#
    {
        return true;
    }
    if( lang == Lang::Ruby )             // parser version 83: every node — a receiver is an expression (see the RUBY note above)
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
// path-precise resolution can leave angle includes unresolved. `isLazy` (kParserVer 72, TS/JS; Ruby since
// parser version 82/83): true when `insideFn` says this call sits inside a closure container — see
// kJsFunctionContainers, the Ruby closure kinds, and captureIncludes' `insideFn` propagation below — or when
// the directive is a Ruby `autoload`. Allocates a std::string → not noexcept.
// `isSymbolic` (parser version 82, Ruby only): the target is a CONSTANT resolved through the corpus's own
// class/module index, never a path — see model.h Include::isSymbolic.
struct DirectiveTarget { std::string target; bool isAngle; bool isLazy; bool isSymbolic; bool isReceiver; };

// `insideFn` exists for exactly the same one branch `lang` does: whether the call_expression being read
// sits inside a TS/JS function body, per captureIncludes' walk — meaningless (and ignored) everywhere else.
DirectiveTarget directiveTargetOf( TSNode n, const char* t, std::string_view src, Lang lang, bool insideFn )
{
    std::string target;
    bool        isAngle    = false;
    bool        isLazy     = false;
    bool        isSymbolic = false;
    bool        isReceiver = false;

    if( kindIs( t, "preproc_include" ) )                       // C++/C/ObjC: exact file path
    {
        target = preprocIncludeTarget( n, src, isAngle );
    }
    else if( kindIs( t, "preproc_call" ) )                     // C++-grammar `#import "x.h"` (ObjC/Metal spelling)
    {
        target = preprocImportTarget( n, src, isAngle );
    }
    else if( kindIs( t, "import_statement" ) )                 // Python `import a` / TS `import … from 'x'`
    {
        // Prefer the grammar's specifier field over slicing the whole statement (LEVER-B B0: the resolver
        // needs the REAL written specifier, not the clause). Empirically confirmed node shapes:
        //   Python: import_statement name:(dotted_name|aliased_import)  → the dotted module `pkg.mod`.
        //   TS/JS:  import_statement source:(string)                    → the quoted specifier `'./x'`.
        // A grammar that lacks the field resolves it to id 0, and fieldChild returns null for it, so a single
        // capture covers both grammars without a per-language branch.
        if( const TSNode src_ = fieldChild( n, NodeField::Source );  !ts_node_is_null( src_ ) )
        {
            target = importSpecifierText( src_, src );                    // TS/JS: strip the surrounding quotes
        }
        else if( const TSNode nm = fieldChild( n, NodeField::Name );  !ts_node_is_null( nm ) )
        {
            target = importSpecifierText( nm, src );                      // Python: the dotted module head
        }
    }
    else if( kindIs( t, "import_from_statement" ) )            // Python `from pkg.mod import Z`
    {
        // module_name:(dotted_name)  → `pkg.mod`;  module_name:(relative_import)  → `.rel` / `..up` (leading
        // dots preserved so the resolver can resolve relative-to-file). The imported-names clause is dropped.
        if( const TSNode mn = fieldChild( n, NodeField::ModuleName );  !ts_node_is_null( mn ) )
        {
            target = importSpecifierText( mn, src );
        }
    }
    else if( kindIs( t, "call_expression" )
             && ( lang == Lang::TypeScript || lang == Lang::JavaScript ) )   // TS/JS `require("./x")` / `import("./x")`
    {
        target = jsModuleLoadTarget( n, src );
        isLazy = insideFn && !target.empty();   // kParserVer 72: a hit found inside a function body is LAZY
    }
    else if( kindIs( t, "command" ) && lang == Lang::Bash )              // Bash `source x.sh` / `. x.sh`
    {
        target = bashSourceTarget( n, src );
    }
    else if( kindIs( t, "function_call" ) && lang == Lang::Lua )         // Lua `require "a.b"`
    {
        target = luaRequireTarget( n, src );
    }
    else if( kindIs( t, "call" ) && lang == Lang::Ruby )                 // Ruby `require_relative "x"` / `require "x"` / `load "x"`
    {
        target = rubyRequireTarget( n, src );
        if( target.empty() && rubyConstantDirective( n, src ) == "autoload" )    // parser version 82: `autoload :Name[, "path"]`
        {
            target = rubyAutoloadTarget( n, src, isSymbolic );
            isLazy = !target.empty();   // an autoload is lazy by definition — the file loads on first use
        }
        if( target.empty() )                                                       // parser version 83: `User.find`, `App::Mailer.deliver`
        {
            target     = rubyReceiverTarget( n, src );                             // empty for every receiver-less call, so the
            isSymbolic = !target.empty();                                          // include/extend/prepend group below still runs
            isReceiver = isSymbolic;
            isLazy     = isSymbolic && insideFn;                                   // inside a closure (kRubyClosureContainers) ⇒ lazy
        }
        // include/extend/prepend name N constants and are emitted by captureIncludes through rubyMixinTargets.
    }
    else if( kindIs( t, "superclass" ) && lang == Lang::Ruby )           // Ruby `class X < Base` (parser version 82)
    {
        target     = rubySuperclassTarget( n, src );
        isSymbolic = !target.empty();
    }
    else if( kindIs( t, "call" ) && lang == Lang::Elixir )               // Elixir `alias`/`import`/`require`/`use`
    {
        // `call` is the node type of EVERY Elixir expression including `defmodule`, so the four-keyword
        // gate inside elixirDirectiveTarget is the whole guard — the same posture as the TS/JS
        // call_expression branch above. The `MyApp.{A, B}` group form returns empty here and is emitted
        // by captureIncludes through elixirAliasGroup, one Include per member.
        target = elixirDirectiveTarget( n, src );
    }
    else if( kindIs( t, "import_header" ) && lang == Lang::Kotlin )   // Kotlin `import a.b.C` / `import a.b.*`
    {
        // No `source:`/`name:` field (this grammar exposes none on import_header — verified against
        // node-types.json, same reason kotlinEnclosingScopeOf walks positionally): find the flat
        // `identifier` child and take its WHOLE span, mirroring Python's dotted-module-head branch
        // above. That span already covers every dotted segment (`kotlin.math.max`), including the
        // wildcard case (`import a.b.*` has `identifier`="a.b" plus a separate wildcard_import
        // sibling this branch does not need to read) and the aliased case (`import a.b.C as D` has
        // `identifier`="a.b.C" plus a separate import_alias sibling naming "D" — the alias is not
        // resolved here, matching every other language's import branch above: none of them resolve
        // a rename either, they all just name the imported target).
        if( const TSNode id = firstChildOfType( n, "identifier" );  !ts_node_is_null( id ) )
        {
            target = importSpecifierText( id, src );
        }
    }
    else if( kindIs( t, "use_declaration" ) )                  // Rust `use crate::a::b;`
    {
        // argument:(scoped_identifier|scoped_use_list|identifier|…)  → `crate::a::b`. A brace group
        // `crate::{a, b}` is kept verbatim; the resolver degrades on it (no unique single-file hit).
        if( const TSNode arg = fieldChild( n, NodeField::Argument );  !ts_node_is_null( arg ) )
        {
            target = importSpecifierText( arg, src );
        }
    }
    else if( kindIs( t, "mod_item" ) )                        // Rust `mod x;` (module-file declaration)
    {
        // A body-LESS `mod x;` declares module `x` in a sibling file (`x.rs` or `x/mod.rs`); a `mod x { … }`
        // with a body is INLINE (no file) → skip it. Prefix `mod:` so the Rust resolver applies the
        // module-file rule, distinct from a bare `use x;`. name:(identifier) → `x`.
        if( ts_node_is_null( fieldChild( n, NodeField::Body ) ) )
        {
            if( const TSNode nm = fieldChild( n, NodeField::Name );  !ts_node_is_null( nm ) )
            {
                if( std::string bare = importSpecifierText( nm, src );  !bare.empty() )
                {
                    target = "mod:" + bare;
                }
            }
        }
    }
    else if(    kindIs( t, "import_declaration" ) )            // Go / Swift — captured but NOT precise-resolved
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
    else if( kindIs( t, "using_directive" ) )
    { // C# `using Foo.Bar;` / `using static Foo;` / `using X = Foo.Bar;`
        target = csharpUsingTarget( n, src );                            // see csharpUsingTarget for the shape rationale
    }
    else if( kindIs( t, "namespace_use_declaration" ) )
    { // PHP `use Foo\Bar;` / `use Foo\Bar as Baz;` / `use function Foo\bar;` / `use Foo\{A, B};`
        // Captured for --uses / --deps visibility, NEVER precise-resolved: PHP has no entry in
        // resolve.h's includeLangOf table, so it falls through to IncludeLang::Other exactly as Java and
        // C# do. The reason is the same one stated there — a PHP namespace does not map 1:1 onto a file
        // (PSR-4 maps it onto a DIRECTORY through a composer.json `autoload` block this tool does not
        // read), so there is no sound string→fileId rule to write, and a wrong narrow is worse than none.
        target = phpUseTarget( n, src );                                 // see phpUseTarget for the shape rationale
    }
    return { std::move( target ), isAngle, isLazy, isSymbolic, isReceiver };
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
// Phase 5 (docs/EVALS.md "Phase 5", kParserVer 77): the NAME a Python import statement binds in the module
// namespace, per imported clause, as a file-scope LocalBindKind::Import RawBind (var = bound name, typeName =
// the module target as written). `import a.b as c` binds `c`; `import a.b` binds `a` (the head — that is the
// name Python puts in the namespace); `from m import x as y` binds `y`; `from m import x` binds `x`; a
// `wildcard_import` binds nothing. The Include record keeps only the module and drops the imported-names
// clause, so without this the bound NAME is unrecoverable resolve-side — and the external-name veto keys on
// exactly that name. Node shapes (tree-sitter-python v0.23.6): import_statement name:(dotted_name|aliased_import)+;
// import_from_statement module_name:(dotted_name|relative_import) name:(dotted_name|aliased_import)* | wildcard_import;
// aliased_import name:(dotted_name) alias:(identifier). startByte = the statement's own start (file scope →
// emitBindings attributes kNoNode); spans {0,0}. Pure-syntactic, deterministic, source order.
inline void capturePythonImportBinds( TSNode stmt, const char* t, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const bool isFrom = ( kindIs( t, "import_from_statement" ) );
    if( !isFrom && !kindIs( t, "import_statement" ) )
    {
        return;
    }
    std::string target;
    if( isFrom )
    {
        const TSNode mn = fieldChild( stmt, NodeField::ModuleName );
        if( ts_node_is_null( mn ) )
        {
            return;
        }
        target = importSpecifierText( mn, src );
    }
    const TSNode        moduleNode = isFrom ? fieldChild( stmt, NodeField::ModuleName ) : TSNode{};
    // One import statement's clause list: the count comes from the input (`from m import ( a, b, … )`),
    // and a comment between two clauses is a further child, so the indexed form was O(children²) here too.
    // No scaling arm exists for it (an import flood is not a shape any corpus produces) — this is the
    // pure-iteration conversion, covered by the byte-identical arms (test/childwalkscalecheck.sh).
    ChildCursor cursor( stmt );
    forEachChild( stmt, cursor.cur, [ & ]( TSNode kid )
    {
        if( ts_node_is_null( kid ) )
        {
            return true;
        }
        const char* kt = ts_node_type( kid );
        if( isFrom && ts_node_eq( kid, moduleNode ) )
        {
            return true;   // the module_name child of a from-import is not a bound name; only the `name:` clauses are
        }
        std::string_view bound;
        std::string      clauseTarget;
        if( kindIs( kt, "aliased_import" ) )
        {
            const TSNode alias = fieldChild( kid, NodeField::Alias );
            const TSNode nm    = fieldChild( kid, NodeField::Name );
            if( ts_node_is_null( alias ) || ts_node_is_null( nm ) )
            {
                return true;
            }
            bound        = pattern::nodeText( alias, src );
            clauseTarget = isFrom ? target : importSpecifierText( nm, src );
        }
        else if( kindIs( kt, "dotted_name" ) )
        {
            const std::string_view whole = pattern::nodeText( kid, src );
            if( isFrom )
            {
                bound        = whole;    // `from m import x` — a bare clause name is an identifier (a dotted one is a syntax error)
                clauseTarget = target;
            }
            else
            {
                const std::size_t dot = whole.find( '.' );
                bound        = ( dot == std::string_view::npos ) ? whole : whole.substr( 0, dot );   // `import a.b` binds `a`
                clauseTarget = std::string( whole );
            }
        }
        else
        {
            return true;   // keywords, punctuation, wildcard_import
        }
        if( bound.empty() || clauseTarget.empty() )
        {
            return true;
        }
        RawBind b;
        b.fileId    = fileId;
        b.startByte = ts_node_start_byte( stmt );
        b.lang      = Lang::Python;
        b.kind      = LocalBindKind::Import;
        b.var.assign( bound );
        b.typeName  = std::move( clauseTarget );
        binds.push_back( std::move( b ) );
        return true;
    } );
}

void captureIncludes( TSNode root, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<Include>& incs, std::vector<RawRef>& refs,
                      std::vector<RawBind>& binds, std::vector<ConstOpen>& constOpens )
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
    // `openIdx` (parser version 83, Ruby only): the index in `constOpens` of the innermost class/module open the
    // frame sits inside — kNoOpenIdx at file level. It rides the frame for the same reason `insideFn` does (the
    // walk keeps no ancestor chain) and exists for the RECEIVER DEDUPE: a constant receiver is recorded once per
    // (file, innermost open, written name). Zeitwerk loads a constant once per process, on its first reference;
    // the second `User.find` in the same body is not a new dependency. The nesting is IN the key because `User`
    // under `module Admin` and `User` under the enclosing module may be two different constants — resolve.h
    // decides which by the same containment, so the two records it receives are exactly the two it can tell apart.
    constexpr std::uint32_t kNoOpenIdx = std::numeric_limits<std::uint32_t>::max();
    struct IncFrame { TSNode node; std::uint16_t depth; bool insideFn; std::uint32_t openIdx; };
    std::vector<IncFrame> stack;
    stack.reserve( 64 );
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( { kids[i - 1], 0, false, kNoOpenIdx } );   // nothing is inside a function or an open at the file root
    }
    HashMap<std::string, std::uint32_t> seenReceivers;   // (openIdx '\x1f' written) → index in incs; per file, receivers only

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
        auto [ target, isAngle, isLazy, isSymbolic, isReceiver ] = directiveTargetOf( n, t, src, lang, frame.insideFn );

        // parser version 82: every Ruby class/module OPEN is recorded for resolve.h's constant index — the span
        // (nesting by containment), the own-body bit, the name as written (model.h ConstOpen). `class`/`module`
        // are containers, so the walk already stands on every open it needs to record; a `class << self` is a
        // singleton_class, not an open of a constant, and is not here.
        std::uint32_t childOpenIdx = frame.openIdx;
        if( lang == Lang::Ruby && ( kindIs( t, "class" ) || kindIs( t, "module" ) ) )
        {
            if( const TSNode nm = fieldChild( n, NodeField::Name ); !ts_node_is_null( nm ) )
            {
                if( std::string written = rubyConstantText( nm, src ); !written.empty() )
                {
                    ConstOpen co;
                    co.fileId        = fileId;
                    co.startByte     = ts_node_start_byte( n );
                    co.endByte       = ts_node_end_byte( n );
                    co.namespaceOnly = rubyNamespaceOnly( n );
                    co.written       = std::move( written );
                    constOpens.push_back( std::move( co ) );
                    childOpenIdx = static_cast<std::uint32_t>( constOpens.size() - 1 );   // everything under n is inside this open
                }
            }
        }

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
                const bool childInsideFn = frame.insideFn || isFunctionLike( lang, t );
                collectChildren( n, cursor.cur, kids );   // safe: the seed iteration above is finished
                for( std::size_t i = kids.size(); i > 0; --i )
                {
                    stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ), childInsideFn, childOpenIdx } );
                }
            }
        }

        if( lang == Lang::Python && !target.empty() )
        {
            capturePythonImportBinds( n, t, fileId, src, binds );   // Phase 5: the bound NAMES, beside the module
        }
        // One directive's emission — the Include record plus its ABS-3 import-role use-site ref. A LAMBDA
        // rather than the straight-line block it used to be for exactly one reason: an Elixir
        // `alias MyApp.{Bar, Baz}` is ONE directive node naming N modules, so N records come off it and
        // the second one cannot be written by falling through this code once.
        const auto emitDirective = [ & ]( std::string tgt, bool symbolic )
        {
            // import-role use-site ref: name = the importable final segment (skip when the target has no
            // identifier head, e.g. a relative `../x` whose head strips to empty → nothing to resolve).
            // A SYMBOLIC (Ruby constant) target emits none: this round is FILE edges only (the same round
            // floor the kParserVer 81 languages state), and importName would read `A::B` as `A`.
            if( std::string nm = symbolic ? std::string{} : importName( tgt ); !nm.empty() )
            {
                RawRef r;
                r.fileId    = fileId;
                r.startByte = ts_node_start_byte( n );   // the DIRECTIVE, not its enclosing #if → file-scope attribution
                r.line      = ts_node_start_point( n ).row + 1;
                r.role      = RefRole::Import;
                r.name      = std::move( nm );
                refs.push_back( std::move( r ) );
            }
            // The site byte. A Ruby `superclass` carries its CLASS's own start byte: the superclass expression is
            // evaluated in the ENCLOSING scope (Ruby has not opened the class yet), and resolve.h's containment
            // is strict at the start, so that byte reads as outside the class — the nesting Ruby actually uses.
            const bool          superclassSite = ( lang == Lang::Ruby && kindIs( t, "superclass" ) );
            const std::uint32_t siteByte       = superclassSite ? ts_node_start_byte( ts_node_parent( n ) ) : ts_node_start_byte( n );
            incs.push_back( { fileId, isAngle, isLazy, symbolic, siteByte, std::move( tgt ) } );
        };

        if( !target.empty() && isReceiver )
        {
            // The receiver dedupe (parser version 83). Key = innermost open + the name as written; the FIRST
            // occurrence in source order carries the byte. The lazy bit is the AND over every occurrence (parser
            // version 86): a receiver inside a method written ABOVE the same receiver at class-body level used to
            // leave the directive lazy, and resolve.h's pair rule — one load-time directive makes the pair
            // load-time — then never saw the load-time site, so the structure lost a real dependency and the
            // answer depended on statement order. A later load-time site now clears the retained record's bit.
            // Declarative directives never come through here: each `include`/`< Base`/`autoload` IS a statement.
            std::string key = std::to_string( frame.openIdx );
            key += '\x1f';
            key += target;
            if( auto [ it, fresh ] = seenReceivers.try_emplace( std::move( key ), 0u ); fresh )
            {
                emitDirective( std::move( target ), isSymbolic );
                it->second = static_cast<std::uint32_t>( incs.size() - 1 );
            }
            else if( !isLazy )
            {
                incs[ it->second ].isLazy = false;
            }
        }
        else if( !target.empty() )
        {
            emitDirective( std::move( target ), isSymbolic );
        }
        else if( lang == Lang::Ruby && kindIs( t, "call" ) )
        {
            // `include A, B` / `extend M` / `prepend P` (parser version 82): N constants off one directive node, in
            // SOURCE order, each a symbolic Include — the Ruby twin of the Elixir alias group below.
            for( std::string& member : rubyMixinTargets( n, src ) )
            {
                emitDirective( std::move( member ), true );
            }
        }
        else if( lang == Lang::Elixir && kindIs( t, "call" ) )
        {
            // The multi-alias group. Members come out in SOURCE order (elixirAliasGroup walks the tuple's
            // named children left to right), so `incs` stays source-ordered and the determinism contract
            // holds exactly as it does for the single-target path.
            for( std::string& member : elixirAliasGroup( n, src ) )
            {
                emitDirective( std::move( member ), false );
            }
        }
    }
}
}   // namespace — ingest_relations.h section of ingest.cpp

}   // namespace rw
