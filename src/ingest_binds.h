#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_binds.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_binds.h — local binding capture, moved VERBATIM from ingest.cpp in the 2026-08-29 split:
// receiver classification (the member-access vocabulary, classifyReceiver/receiverOf), the P2-D
// local-variable TYPE binding capture (declarator/ctor/written-type readers), the L3
// fn-pointer/callback binding layer with both r9 noise gates (assignment + declaration arms,
// FnBindGateState, the pending-resolve queues), shadow-scope declaration capture (lambdas, params,
// scope spans), and the BindCtx visitors (bindsVisitNode/bindsFinalize) the side-capture stream
// drives. Everything that binds a NAME inside a function body to a type or a function. Same
// contract as every ingest_*.h: reopens `namespace rw` and the unnamed namespace inside it — one
// TU, one unnamed namespace, internal linkage unchanged, zero new API surface — under the
// RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// ── receiver capture: the member-access vocabulary, one declarative place ────────────────────────────
// The two shapes whose receiver we inspect: C++/ObjC `field_expression` (`.argument` / `.field`) and
// Python `attribute` (`.object` / `.attribute`). Named here rather than re-spelled per call site because
// the depth-2 chain walk below applies exactly the same three questions twice, one level apart.
// Ruby: tree-sitter-ruby has no member-access node of its own — `recv.m(args)` IS the `call` node, with
// `receiver:` / `method:` fields, and a receiver-less `m(args)` is the same node kind with no `receiver:`
// field. So `call` is the member-access node for Ruby and a null receiver is the bare shape — receiverOf's
// existing null-receiver return already reads that as RecvKind::None (test/rubyscopecheck.sh, Rule 1 arms).
// DISCLOSED GAP, not an oversight: Kotlin is absent here. `A.f()` parses to a `navigation_expression`
// (verified against the vendored grammar), which this function does not recognize, so EVERY Kotlin
// call site — bare `f()` and explicitly-qualified `A.f()` alike — classifies RecvKind::None. The
// practical cost: an explicit receiver that WOULD narrow a same-name collision (two Kotlin
// classes/objects each defining `f`, called as `A.f()` vs `B.f()`) currently does not — both stay
// candidates, same as a genuinely bare call. graph.h's JVM bridge doesn't cause this (it is real and
// present for Kotlin-only collisions too, no Java involved); adding this is a real feature — a
// navigation_expression arm here plus a Kotlin case in memberAccessReceiver/memberAccessField below
// — not a bug fix, and is out of scope for this port.
inline bool isMemberAccessNode( const char* t, Lang lang ) noexcept
{
    if( lang == Lang::Cpp || lang == Lang::ObjC ) { return kindIs( t, "field_expression" ); }
    if( lang == Lang::Python )                    { return kindIs( t, "attribute" ); }
    if( lang == Lang::Ruby )                      { return kindIs( t, "call" ); }
    return false;
}

inline TSNode memberAccessReceiver( TSNode access, Lang lang ) noexcept
{
    if( lang == Lang::Python ) { return fieldChild( access, NodeField::Object ); }
    if( lang == Lang::Ruby )   { return fieldChild( access, NodeField::Receiver ); }
    return fieldChild( access, NodeField::Argument );
}

inline TSNode memberAccessField( TSNode access, Lang lang ) noexcept
{
    if( lang == Lang::Python ) { return fieldChild( access, NodeField::Attribute ); }
    if( lang == Lang::Ruby )   { return fieldChild( access, NodeField::Method ); }
    return fieldChild( access, NodeField::Field );
}

// The classified receiver of one call site. `var` is set for NamedVar / FieldOfVar, `field` for
// FieldOfThis / FieldOfVar; both "" for None / ThisObj.
struct RecvShape
{
    RecvKind    kind = RecvKind::None;
    std::string var;
    std::string field;
};

// One receiver NODE → its RecvShape. `allowChain` is the ONE-hop bound: true at the call's immediate
// receiver (a member-access receiver descends exactly one level, re-asking the same questions of its
// INNER receiver), false inside that descent — so a depth-3 chain's inner member-access classifies None
// and the whole chain degrades to the honest §2a split. `test/chainguardcheck.sh` arm (h) pins the
// bound, and the residual it leaves, as disclosed.
inline RecvShape classifyReceiver( TSNode node, Lang lang, std::string_view src, bool allowChain )
{
    const char* rt = ts_node_type( node );
    if( kindIs( rt, "this" ) )
    {
        return { RecvKind::ThisObj, {}, {} }; // C++ `this`
    }
    if( lang == Lang::Ruby && kindIs( rt, "self" ) )
    {
        return { RecvKind::ThisObj, {}, {} }; // Ruby `self` — its own node kind, not an identifier
    }
    if( kindIs( rt, "identifier" ) )
    {
        const std::string_view v = pattern::nodeText( node, src );
        if( v.empty() )
        {
            return {};
        }
        if( lang == Lang::Python && v == "self" )
        {
            return { RecvKind::ThisObj, {}, {} }; // Python `self`
        }
        return { RecvKind::NamedVar, std::string( v ), {} };                          // `x` — Rule 2 fuel
    }
    if( lang == Lang::Python && kindIs( rt, "call" ) )
    { // Phase 5: `super().m()` / `super(C, self).m()` — the receiver is a CALL of the identifier `super`
        const TSNode fn = fieldChild( node, NodeField::Function );
        if( !ts_node_is_null( fn ) && kindIs( ts_node_type( fn ), "identifier" ) && pattern::nodeText( fn, src ) == "super" )
        {
            return { RecvKind::SuperObj, {}, {} };
        }
        return {};   // any other call receiver → not one-hop
    }
    if( allowChain && isMemberAccessNode( rt, lang ) )
    { // depth 2: the receiver is ITSELF one member access — `this->FIELD.m()` / `base.FIELD.m()`
        const TSNode innerRecv  = memberAccessReceiver( node, lang );
        const TSNode innerField = memberAccessField( node, lang );
        if( ts_node_is_null( innerRecv ) || ts_node_is_null( innerField ) )
        {
            return {};
        }
        // the intermediate must be a plain NAME — a template/computed/parenthesized form is not a field
        const char* ift = ts_node_type( innerField );
        if( !kindIs( ift, "field_identifier" ) && !kindIs( ift, "identifier" ) )
        {
            return {};
        }
        const std::string_view fieldTxt = pattern::nodeText( innerField, src );
        if( fieldTxt.empty() )
        {
            return {};
        }
        const RecvShape base = classifyReceiver( innerRecv, lang, src, false );
        if( base.kind == RecvKind::ThisObj )
        {
            return { RecvKind::FieldOfThis, {}, std::string( fieldTxt ) };            // `this->m_pool.run()` / `self.pool.acquire()`
        }
        if( base.kind == RecvKind::NamedVar )
        {
            return { RecvKind::FieldOfVar, base.var, std::string( fieldTxt ) };       // `cfg.opts.enable()`
        }
        return {};   // depth-3 or richer base → not decidable in one hop; degrade to §2a
    }
    return {};   // parenthesized / subscripted / call receiver → not one-hop
}

// P2-D RECEIVER capture: classify the call-site receiver of `recv.method()` / `recv->method()` so
// resolve.h can narrow before the ambiguous §2a name spray. `nameNode` is the @name capture (the called
// identifier). When it is the `.field`/`.attribute` of a member-access node, inspect that node's
// receiver (`.argument` in C++ `field_expression`, `.object` in Python `attribute`):
//   `this`/`self`        → ThisObj  (the enclosing class is definitive — Rule 1)
//   a bare `(identifier)` → NamedVar, recvVar = the variable text (the var's type pins the method — Rule 2)
//   ONE more member access whose OWN receiver is `this`/`self` or a bare identifier → FieldOfThis /
//     FieldOfVar, carrying the intermediate field name (`this->m_pool.run()` → field "m_pool";
//     `cfg.opts.enable()` → var "cfg", field "opts"). NO resolve rule consumes these yet: the receiver
//     kind exists so the five `recv == RecvKind::None` guard sites stop misclassifying a chained
//     receiver as a BARE name — Rule 1's bareCish arm wrong-narrowed `this->m_pool.run()` to the
//     caller's own class, and shadow suppression deleted `this->m_cfg.enable()` under a local named
//     `enable` (docs/EVALS.md §4 "Receiver-guard misfires"; the names carried here make a future
//     chain-resolution rule resolve-side only, with no second re-parse).
//   `super()` / `super(C, self)` (Python) → SuperObj (Phase 5: resolves through the bases only)
//   anything else (a depth-3 chain, `(expr)`, subscripts, a non-super call in the chain, …) → FieldOfVar
//     with an EMPTY recvVar — "a member access, receiver undecidable" (Phase 5; was None, which the five
//     bare-name guard sites misread as a BARE call). The bound is ONE intermediate hop, deliberately: past
//     that the receiver is too rich to decide syntactically. `test/chainguardcheck.sh` arm (h) pins the
//     bound: the depth-3 call now takes the honest ladder, never Rule 1's enclosing-class pin.
// Pure-syntactic, deterministic, allocation-light: at most two short identifier copies, and none at all
// for the None/ThisObj shapes that dominate.
inline RecvShape receiverOf( TSNode nameNode, Lang lang, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) )
    {
        return {};
    }
    if( !isMemberAccessNode( ts_node_type( parent ), lang ) )
    {
        return {};
    }

    const TSNode recvNode = memberAccessReceiver( parent, lang );
    if( ts_node_is_null( recvNode ) )
    {
        return {};
    }
    RecvShape rs = classifyReceiver( recvNode, lang, src, /*allowChain=*/ true );
    if( rs.kind == RecvKind::None )
    {
        // Phase 5 (docs/EVALS.md "Phase 5", kParserVer 77): a member access whose receiver is too rich to
        // classify (a depth-3 chain, a call other than `super()`, a subscript, a literal, a parenthesized
        // expression) is still a MEMBER ACCESS — never a bare name. Stamped FieldOfVar with an EMPTY recvVar,
        // the convention stampMemberReceiver already uses for Read/Write refs, so the `recv == None` guard
        // sites (Rule 1's bare arm, shadow suppression, the external-name veto's bare arms) read None as
        // "truly bare". Found by the veto's own precision listing: `self.to_cartesian().sum()` was read as a
        // bare builtin `sum(…)` and refused. Closes the depth-3 residual test/chainguardcheck.sh arm (h) pinned.
        rs.kind = RecvKind::FieldOfVar;
    }
    return rs;
}

// ── P2-D Rule 2 LOCAL-VARIABLE TYPE BINDING capture (`Foo x;` → x:Foo) ───────────────────────────────
// Walk a node subtree and emit one RawBind per local variable whose TYPE is syntactically decidable, so a
// later `x.m()`/`x->m()` can narrow to `typeName::m`. Pure-syntactic, deterministic, allocation-light:
// it reads exactly the declaration/assignment shapes ground-truthed from the grammars (see the gate fixtures).
//   * The recorded typeName is the WRITTEN type's final segment (`ns::Foo` → `Foo`). It is matched against
//     class/struct symbol NAMES in buildGraph, which is the conservative safety net: an inferred type from a
//     constructor-call (`auto x = Foo()`) only narrows if `Foo` actually names a class — else it drops.
//   * Only the named-receiver shape is useful downstream, so only bare-identifier targets are recorded
//     (member targets `self.x`/`obj.f` are not — `receiverOf` doesn't capture those as recvVar either).

// the innermost bare `(identifier)` reached by unwrapping pointer/reference/parenthesized declarators —
// the actual variable name of a C++ declarator. "" if the declarator isn't a single named variable.
inline std::string_view declaratorVarName( TSNode decl, std::string_view src )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( kindIs( dt, "identifier" ) )
        {
            const std::uint32_t a = ts_node_start_byte( decl ), b = ts_node_end_byte( decl );
            return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
        }
        // unwrap a pointer/reference/parenthesized declarator to its inner `declarator` child
        const TSNode inner = fieldChild( decl, NodeField::Declarator );
        if( ts_node_is_null( inner ) )
        {
            return {};
        }
        decl = inner;
    }
    return {};
}

// member-variable round (card A3): the variable name of a PARAMETER declarator, which is declaratorVarName's
// answer plus one shape it refuses on purpose: a reference_declarator holds its inner declarator as an UNNAMED
// child (`Counter& c` — the `&` is the only anonymous sibling), so the `declarator` field probe is null there.
// Unwrapped HERE, for the ParamType record alone — widening declaratorVarName itself would mint Rule-2 Type
// records for `Foo& x = …` locals too and move call edges outside this round's gate.
inline std::string_view paramDeclaratorVarName( TSNode decl, std::string_view src )
{
    if( !ts_node_is_null( decl ) && kindIs( ts_node_type( decl ), "reference_declarator" )
        && ts_node_is_null( fieldChild( decl, NodeField::Declarator ) ) && ts_node_named_child_count( decl ) > 0 )
    {
        decl = ts_node_named_child( decl, 0 );
    }
    return declaratorVarName( decl, src );
}

// the type NAME of a constructor-style RHS value node: `Foo()` (call_expression) or `new Foo()`
// (new_expression). Final segment of the callee/constructor identifier. "" if the value isn't a
// plain constructor call (so `auto x = makeFoo()` infers nothing here unless `makeFoo` names a class —
// and the class-name filter in buildGraph is what makes that safe).
inline std::string ctorTypeOf( TSNode value, std::string_view src )
{
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    const char* vt = ts_node_type( value );
    TSNode      idn {};
    if( kindIs( vt, "call_expression" ) )
    { // C++/TS `Foo()`
        idn = fieldChild( value, NodeField::Function );
    }
    else if( kindIs( vt, "new_expression" ) )
    { // C++/TS `new Foo()`
        idn = fieldChild( value, NodeField::Constructor );
    }
    if( ts_node_is_null( idn ) )
    {
        return {};
    }
    const char* it = ts_node_type( idn );
    if( !kindIs( it, "identifier" ) && !kindIs( it, "type_identifier" ) && !kindIs( it, "qualified_identifier" ) && !kindIs( it, "scoped_identifier" ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    return ( a <= b && b <= src.size() ) ? finalSegment( src.substr( a, b - a ) ) : std::string{};
}

// the written type name of a `type:`-field type node (`type_identifier`, or a qualified/scoped one). "" for
// `auto`/`placeholder_type_specifier`/templated/decltype types — those fall back to constructor inference.
inline std::string writtenTypeOf( TSNode typeNode, std::string_view src )
{
    if( ts_node_is_null( typeNode ) )
    {
        return {};
    }
    const char* tt = ts_node_type( typeNode );
    if( kindIs( tt, "type_identifier" ) || kindIs( tt, "qualified_identifier" )
        || kindIs( tt, "scoped_type_identifier" ) )
    {
        const std::uint32_t a = ts_node_start_byte( typeNode ), b = ts_node_end_byte( typeNode );
        return ( a <= b && b <= src.size() ) ? finalSegment( src.substr( a, b - a ) ) : std::string{};
    }
    return {};   // auto / template / decltype — type not directly written → try the initializer
}

// ── L3 fn-pointer/callback binding capture helpers ───────────────────────────────────────────────────

// the bound-function TARGET of an initializer/assignment RHS value node, for a var→FUNCTION binding:
//   `&alpha` / `&ns::alpha` (address-of) → "alpha" / "ns::alpha";  `alpha` / `ns::alpha` (bare) → same;
//   `[](){...}` (lambda) → kFnBindLambdaTarget.  "" for everything else (a call, a literal, arithmetic —
// not a recognizable single function). `wasBareIdent` reports the bare-IDENTIFIER shape so the caller can
// apply the primitive-type noise gate (`int a = b;` is almost never a function copy; `H h = beta;` through
// a typedef legitimately is).
inline std::string fnBindTargetOf( TSNode value, std::string_view src, bool& wasBareIdent )
{
    wasBareIdent = false;
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    const char* vt = ts_node_type( value );
    if( kindIs( vt, "lambda_expression" ) )
    {
        return std::string( kFnBindLambdaTarget );
    }
    TSNode idn       = value;
    bool   addressOf = false;
    if( kindIs( vt, "pointer_expression" ) )
    {
        // only the ADDRESS-OF form — `*p` is also a pointer_expression, and a dereference names no function.
        const TSNode op = ts_node_child( value, 0 );
        if( ts_node_is_null( op ) || !kindIs( ts_node_type( op ), "&" ) )
        {
            return {};
        }
        idn = fieldChild( value, NodeField::Argument );
        if( ts_node_is_null( idn ) )
        {
            return {};
        }
        addressOf = true;
    }
    const char* it = ts_node_type( idn );
    if( !kindIs( it, "identifier" ) && !kindIs( it, "qualified_identifier" ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    if( a > b || b > src.size() )
    {
        return {};
    }
    wasBareIdent = !addressOf && kindIs( it, "identifier" );
    return std::string( src.substr( a, b - a ) );
}

// the shape a possibly fn-pointer declarator chain (`(*fn)()` → "fn") presents, descending through
// function/parenthesized/pointer/reference declarators. `sawFn` reports crossing a function_declarator —
// the explicit fn-pointer syntax that licenses a bare-identifier initializer even under a primitive written
// type (`void (*fn)() = handler;`); `sawRef` a reference_declarator (`H& r = fn;`), where the reference
// ALIASES its initializer, so the caller must treat the bound-to variable as ESCAPED (clobbered) and never
// emit a positive for the alias; `sawPtr` a pointer_declarator, which is what separates the two shapes the
// type node alone cannot tell apart — `void (*fp)()` (a fn-pointer VARIABLE: sawFn AND sawPtr) from
// `void fp()` (a function DECLARATION: sawFn alone), which declares no variable at all. declaratorVarName
// (Rule 2) is NOT reused: parenthesized_declarator and reference_declarator carry their inner declarator as
// an UNNAMED child, which a field-only unwrap cannot reach. An array_declarator bails — an ARRAY of fn
// pointers is table territory, never a single-var binding (its indexed call must stay unresolved).
struct FnBindDeclShape
{
    std::string_view name;
    bool             sawFn  = false;
    bool             sawPtr = false;
    bool             sawRef = false;
};

inline FnBindDeclShape fnDeclaratorShape( TSNode decl, std::string_view src )
{
    FnBindDeclShape shape;
    for( int guard = 0; guard < 10 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( kindIs( dt, "identifier" ) )
        {
            const std::uint32_t a = ts_node_start_byte( decl ), b = ts_node_end_byte( decl );
            shape.name = ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
            return shape;
        }
        if( kindIs( dt, "array_declarator" ) )
        {
            return shape;
        }
        const bool isRef = ( kindIs( dt, "reference_declarator" ) );
        shape.sawFn  = shape.sawFn  || kindIs( dt, "function_declarator" );
        shape.sawPtr = shape.sawPtr || kindIs( dt, "pointer_declarator" );
        shape.sawRef = shape.sawRef || isRef;
        TSNode inner = fieldChild( decl, NodeField::Declarator );
        if( ts_node_is_null( inner ) && ( isRef || kindIs( dt, "parenthesized_declarator" ) ) )
        {
            // the parenthesized/reference inner declarator is an UNNAMED child — take the first named one
            if( ts_node_named_child_count( decl ) > 0 )
            {
                inner = ts_node_named_child( decl, 0 );
            }
        }
        if( ts_node_is_null( inner ) )
        {
            return shape;
        }
        decl = inner;
    }
    return shape;
}

// tree-sitter-cpp MIS-PARSES a raw fn-pointer declaration inside a function body —
// `void (*fn)() = &alpha;` — as an assignment_expression whose LEFT is
//   call_expression( function: call_expression( function: primitive_type, arguments: ((*fn)) ), arguments: () )
// (the C grammar parses the same statement as a true declaration; only C++ takes the expression branch —
// ground-truthed with an AST dump against the vendored grammars, 2026-08-08). Decode the variable name from
// that shape. The inner callee must be a PRIMITIVE type — `void(...)` is never callable, so the shape is
// unambiguous evidence of a declaration; an identifier callee (`H (*g)()`, but equally REAL code
// `foo(*p)() = x;` assigning through a call result) stays undecoded — conservative, no false binding.
inline std::string_view misparsedFnPtrDeclVar( TSNode lhs, std::string_view src )
{
    if( ts_node_is_null( lhs ) || !kindIs( ts_node_type( lhs ), "call_expression" ) )
    {
        return {};
    }
    const TSNode inner = fieldChild( lhs, NodeField::Function );
    if( ts_node_is_null( inner ) || !kindIs( ts_node_type( inner ), "call_expression" ) )
    {
        return {};
    }
    const TSNode ty = fieldChild( inner, NodeField::Function );
    if( ts_node_is_null( ty ) || !kindIs( ts_node_type( ty ), "primitive_type" ) )
    {
        return {};
    }
    const TSNode args = fieldChild( inner, NodeField::Arguments );
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) != 1 )
    {
        return {};
    }
    const TSNode pe = ts_node_named_child( args, 0 );
    if( !kindIs( ts_node_type( pe ), "pointer_expression" ) )
    {
        return {};
    }
    const TSNode op = ts_node_child( pe, 0 );
    if( ts_node_is_null( op ) || !kindIs( ts_node_type( op ), "*" ) )
    {
        return {};
    }
    const TSNode idn = fieldChild( pe, NodeField::Argument );
    if( ts_node_is_null( idn ) || !kindIs( ts_node_type( idn ), "identifier" ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
}

// L3: an assignment whose RHS is not a recognizable single function — a CLOBBER site, emitted as a
// kFnBindClobberTarget record at the end of the walk IF the var has a fn binding in the same file.
struct FnBindClobber
{
    std::string   var;
    std::uint32_t startByte = 0;
};

// ── L3 VALUE-ASSIGNMENT NOISE GATE (r9 fix round) ────────────────────────────────────────────────────
// The DECLARATION arm gates its bare-identifier initializer on the written type (`int a = b;` is a copy,
// not a function). The ASSIGNMENT arm carries no type node at all, so before this gate EVERY `x = y;` with
// a bare-identifier RHS minted an FnAssign — `std::string line; line = zzz;` included. Two measured harms,
// both from a binding that names no function anybody could call: shadowSuppressedSite VETOES local-shadow
// suppression for any name carrying an L3 binding (calls THROUGH a bound variable must keep resolving), so
// the local handed its every read/write back to the function it shadows; and buildFnPtrBindTables' file-
// scope sweep keys FnAssign records by VAR NAME ALONE across the whole corpus, so one bogus record
// TOMBSTONED a genuine, never-clobbered file-scope binding of the same name in an unrelated file.
// The gate asks the file's own declarations of that name what the variable IS:
//   * PROVEN VALUE — declared with a concrete written type that is no function-pointer alias → the
//     assignment is a copy: no positive, a CLOBBER instead (exactly what `fn = getHandler()` records),
//     inert unless the name holds a real binding here and correctly tombstoning it when it does;
//   * FN-CAPABLE — a fn-pointer declarator (`void (*fp)()`) or a fn-pointer alias type (`H fp;`) → mint,
//     and this wins over any value evidence for the same name (recall-safe when a file reuses a name);
//   * NEITHER — `auto`, `decltype`, a template type, or a name this file never declares (a global, a
//     member, an extern): UNKNOWN, and unknown MINTS, exactly as before. When in doubt, don't gate.
// File-scoped and name-based, like every other L3 table: evidence from one function's declarations reaches
// another's assignment of the same name. That over-approximation runs toward NOT minting a binding, which
// is the side that can only cost a disclosed edge, never invent one. Address-of (`fn = &beta`) and lambda
// RHS forms are self-evidencing and never reach the gate.
// Each fact carries the DEFINITION it was declared inside, so one file declaring `std::string run;` in one
// function and `void (*run)();` in another gets both answers right; a file-scope declaration carries {0,0}
// and applies everywhere. This is a function-granular scope, deliberately coarser than the shadow spans in
// model.h — it decides what a NAME can hold, not which sites a declaration claims.
struct FnBindVarTypeFact
{
    std::string   var;
    std::string   typeName;              // final segment of a WRITTEN type name; "" for the unnamed kinds
    std::uint32_t scopeStart   = 0;      // the enclosing definition's byte span; {0,0} = file scope
    std::uint32_t scopeEnd     = 0;
    bool        concreteType  = false;   // the type node's spelling FIXES the type (never auto/decltype/template)
    bool        fnPtrVariable = false;   // the declarator chain is a function POINTER, not a plain value
};

// a bare-identifier assignment held back until the walk ends, when the file's full declaration evidence —
// including declarations the DFS has not reached yet — decides whether it mints a binding or a clobber.
// Deferring is what keeps the verdict independent of walk order, and so of the AST's shape.
struct PendingFnBindAssign
{
    std::string   var;
    std::string   target;
    std::uint32_t startByte = 0;
};

// a bare-identifier DECLARATION initializer held back the same way, and for one reason only: the fn-pointer
// ALIAS table is not complete until the walk ends, and a `typedef void (*H)();` written BELOW `H fp = beta;`
// is the difference between a binding and a copy. Unlike its assignment sibling this record carries its own
// verdict material — the declaration's WRITTEN TYPE, read straight off the node — because a declaration IS
// the variable and needs no file-wide fact lookup to say what it holds.
struct PendingFnBindDecl
{
    std::string   var;
    std::string   target;
    std::string   typeName;              // final segment of the written type; "" for the unnamed concrete kinds
    std::uint32_t startByte    = 0;
    bool          concreteType = false;  // the spelling FIXES the type (never auto/decltype/template)
};

// the gate's whole per-file state: the declared-variable type facts, the file's function-pointer type
// aliases, and the assignments AND declarations held back until both of those are complete. One object
// because they have no independent life — filled by one walk and spent together the moment it ends.
struct FnBindGateState
{
    std::vector<FnBindVarTypeFact>   facts;
    std::vector<PendingFnBindAssign> pending;
    std::vector<PendingFnBindDecl>   pendingDecl;
    HashMap<std::string, char>       aliases;
};

// true when a `type:` field node is a CONCRETE written type — one whose spelling alone fixes what the
// variable is. `name` receives the final segment for the NAMED kinds (the only ones a typedef can make a
// function pointer); the built-in and class/enum-body kinds can never be one and leave it empty. Everything
// else — `auto`, `decltype`, and any type carrying TEMPLATE ARGUMENTS — is dependent, not concrete: the
// spelling of `std::function<void()>` says nothing about callability the way `std::string` does.
inline bool concreteWrittenType( TSNode typeNode, std::string_view src, std::string& name )
{
    name.clear();
    if( ts_node_is_null( typeNode ) )
    {
        return false;
    }
    const char* tt = ts_node_type( typeNode );
    if( kindIs( tt, "primitive_type" ) || kindIs( tt, "sized_type_specifier" )
        || kindIs( tt, "struct_specifier" ) || kindIs( tt, "class_specifier" )
        || kindIs( tt, "union_specifier" ) || kindIs( tt, "enum_specifier" ) )
    {
        return true;
    }
    if( !kindIs( tt, "type_identifier" ) && !kindIs( tt, "qualified_identifier" )
        && !kindIs( tt, "scoped_type_identifier" ) )
    {
        return false;
    }
    const std::string_view text = nodeTextOf( typeNode, src );
    if( text.empty() || text.find( '<' ) != std::string_view::npos )
    {
        return false;
    }
    name = finalSegment( text );
    return true;
}

// the TYPE-ALIAS name a node declares for a FUNCTION-POINTER type — `typedef void (*H)();` and
// `using H = void(*)();` both yield "H"; every other typedef/alias yields "". This is the one piece of
// evidence that separates a callable alias from an ordinary class name, both of which reach a declaration
// as a bare `type_identifier`. Same-file only, which is the disclosed limit: an alias declared in a header
// is invisible to a per-file parse, so a variable of that type stays UNKNOWN — and unknown still mints.
inline std::string_view fnPtrAliasName( TSNode n, const char* t, std::string_view src )
{
    if( kindIs( t, "alias_declaration" ) )
    {
        const TSNode desc = fieldChild( n, NodeField::Type );
        if( ts_node_is_null( desc ) )
        {
            return {};
        }
        const TSNode abst = fieldChild( desc, NodeField::Declarator );
        if( ts_node_is_null( abst ) || !kindIs( ts_node_type( abst ), "abstract_function_declarator" ) )
        {
            return {};
        }
        const TSNode nm = fieldChild( n, NodeField::Name );
        return ts_node_is_null( nm ) ? std::string_view{} : nodeTextOf( nm, src );
    }
    if( !kindIs( t, "type_definition" ) )
    {
        return {};
    }
    // O(children): the declarator-field scan rides the cursor's own O(1) field name instead of
    // `ts_node_field_name_for_child( n, i )`, which restarts the child iterator (src/infra/tschildren.h).
    // A typedef's width is input-controlled — a comment sits between `typedef` and the declarator as a
    // direct child like any other extra (test/childwalkscalecheck.sh, arm B7).
    std::string_view found;
    ChildCursor      cursor( n );
    forEachChild( n, cursor.cur, [ & ]( TSNode c )
    {
        const char* fname = ts_tree_cursor_current_field_name( &cursor.cur );
        if( fname == nullptr || !kindIs( fname, "declarator" ) )
        {
            return true;
        }
        TSNode d       = c;
        bool   crossed = false;
        for( int guard = 0; guard < 10 && !ts_node_is_null( d ); ++guard )
        {
            const char* dt = ts_node_type( d );
            if( kindIs( dt, "type_identifier" ) )
            {
                found = crossed ? nodeTextOf( d, src ) : std::string_view{};
                return false;   // the indexed loop returned from here
            }
            if( kindIs( dt, "function_declarator" ) )
            {
                crossed = true;
            }
            TSNode inner = fieldChild( d, NodeField::Declarator );
            if( ts_node_is_null( inner ) && ts_node_named_child_count( d ) > 0 )
            {
                inner = ts_node_named_child( d, 0 );
            }
            d = inner;
        }
        return true;
    } );
    return found;
}

// the byte span of the DEFINITION a node sits inside — a function body or a lambda, whichever encloses it
// first. {0,0} at file/namespace/class scope, which the gate reads as "applies everywhere": a file-scope
// variable IS in scope in every function below it.
inline std::pair<std::uint32_t, std::uint32_t> enclosingDefSpan( TSNode n )
{
    TSNode p = ts_node_parent( n );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( kindIs( pt, "function_definition" ) || kindIs( pt, "lambda_expression" ) )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ) };
        }
        p = ts_node_parent( p );
    }
    return { 0u, 0u };
}

// record one declaration node's type facts — one per DECLARED VARIABLE. Covers the three shapes that
// declare a name a later `x = y;` can target: a block/file `declaration`, a function `parameter_declaration`
// (a value parameter reassigned from another parameter is the same copy), and a `field_declaration`.
inline void collectFnBindTypeFacts( TSNode n, const char* t, std::string_view src, std::vector<FnBindVarTypeFact>& facts )
{
    if( !kindIs( t, "declaration" ) && !kindIs( t, "parameter_declaration" )
        && !kindIs( t, "optional_parameter_declaration" ) && !kindIs( t, "field_declaration" ) )
    {
        return;
    }
    std::string typeName;
    const bool  concrete           = concreteWrittenType( fieldChild( n, NodeField::Type ), src, typeName );
    const auto [ scopeStart, scopeEnd ] = enclosingDefSpan( n );
    // O(children), on the cursor's O(1) field name — see fnPtrAliasName above and arm B7.
    ChildCursor cursor( n );
    forEachChild( n, cursor.cur, [ & ]( TSNode c )
    {
        const char* fname = ts_tree_cursor_current_field_name( &cursor.cur );
        if( fname == nullptr || !kindIs( fname, "declarator" ) )
        {
            return true;
        }
        TSNode d = c;
        if( kindIs( ts_node_type( d ), "init_declarator" ) )
        {
            d = fieldChild( d, NodeField::Declarator );
        }
        const FnBindDeclShape shape = fnDeclaratorShape( d, src );
        if( shape.name.empty() || ( shape.sawFn && !shape.sawPtr ) )
        {
            return true;   // nameless, an array of pointers, or a plain function DECLARATION — no variable here
        }
        facts.push_back( { std::string( shape.name ), typeName, scopeStart, scopeEnd, concrete, shape.sawFn && shape.sawPtr } );
        return true;
    } );
}

// the gate's whole per-node collection: a declaration's variable type facts AND, from the same node, any
// function-pointer type alias it declares. `cFamily` is taken rather than checked at the call site so the
// walk carries ONE unconditional line for the evidence — a `declaration` node feeds both the L3 capture
// arms and the type facts here, and a typedef/alias node reaches neither of those arms.
inline void collectFnBindGateEvidence( TSNode n, const char* t, std::string_view src, bool cFamily, FnBindGateState& gate )
{
    if( !cFamily )
    {
        return;
    }
    collectFnBindTypeFacts( n, t, src, gate.facts );
    if( const std::string_view alias = fnPtrAliasName( n, t, src ); !alias.empty() )
    {
        gate.aliases.try_emplace( std::string( alias ), 1 );
    }
}

// the gate's verdict for one assignment: true ⇒ the file PROVED this name is a value variable where the
// assignment sits, so it is a copy and mints no binding. Only facts whose definition span CONTAINS the
// assignment count (plus file-scope ones, which contain everything); among those, fn-pointer evidence wins
// outright, and with no fact at all the name is unknown and the answer is false (mint, exactly as before).
inline bool fnBindProvenValueVar( std::string_view var, std::uint32_t startByte,
                                  const std::vector<FnBindVarTypeFact>& facts,
                                  const HashMap<std::string, char>& fnAliases )
{
    bool proven = false;
    for( const FnBindVarTypeFact& f : facts )
    {
        if( f.var != var )
        {
            continue;
        }
        if( f.scopeEnd != 0u && ( startByte < f.scopeStart || startByte >= f.scopeEnd ) )
        {
            continue;   // declared inside a definition this assignment is not in — a different variable
        }
        const bool aliasTyped = !f.typeName.empty() && fnAliases.find( f.typeName ) != fnAliases.end();
        if( f.fnPtrVariable || aliasTyped )
        {
            return false;
        }
        proven = proven || ( f.concreteType && !aliasTyped );
    }
    return proven;
}

// where a bind-record SITS: its own position (for enclosing-def attribution) plus, on VarDecl records,
// the declaring BLOCK's byte range — the shadow scope model.h's suppressShadowedReferences tests sites
// against ({0,0} on every other kind: contains nothing, inert by construction).
struct BindSite
{
    std::uint32_t startByte = 0;
    std::uint32_t spanStart = 0;
    std::uint32_t spanEnd   = 0;
};

// the ONE bind-record emitter. A nameless declarator records nothing. kind=VarDecl is the r9 shadow-
// evidence record: typeName stays EMPTY on it (shadow evidence, not narrowing fuel — nothing downstream
// ever reads a type off it), so the empty-typeName refusal applies to every OTHER kind, where it is
// load-bearing for Rule 2 (an undecidable type must degrade to §2a, not mint a half-record).
inline void pushRawBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                         BindSite site, LocalBindKind kind, std::vector<RawBind>& binds )
{
    if( var.empty() || ( typeName.empty() && kind != LocalBindKind::VarDecl ) )
    {
        return;
    }
    RawBind b;
    b.fileId    = fileId;
    b.startByte = site.startByte;
    b.lang      = lang;
    b.kind      = kind;
    b.spanStart = site.spanStart;
    b.spanEnd   = site.spanEnd;
    b.var.assign( var );
    b.typeName  = std::move( typeName );
    binds.push_back( std::move( b ) );
}

// emit a Rule-2 binding from one declared variable: prefer the WRITTEN type; else infer from a
// constructor-style initializer (`auto x = Foo()`). Records nothing when neither is decidable.
inline void emitBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                      std::uint32_t startByte, std::vector<RawBind>& binds )
{
    pushRawBind( fileId, lang, var, std::move( typeName ), BindSite{ startByte, 0u, 0u }, LocalBindKind::Type, binds );
}

// the scope a `declaration` node's names shadow within: the byte span, plus whether that span came from a
// PLAIN BLOCK (the only kind the declaration-point narrowing below applies to). {0,0} when nothing encloses
// (file/namespace/class scope): such a record can contain no site and is inert by construction.
struct ShadowScope
{
    std::uint32_t start      = 0;
    std::uint32_t end        = 0;
    bool          plainBlock = false;
};

// r9 shadow fix round (A5, iteration 3): the byte span a declaration's names are scoped to. A declaration
// in a control statement's HEADER — for-init (`for (int run = 0; ...)`), if/while/switch condition
// (`if (int run = f())`) — scopes to THAT STATEMENT's full span (C++: the variable lives for the whole
// statement, else-branch included), NOT the enclosing block: the header declaration is a SIBLING of the
// statement's body, so the plain compound_statement walk of iteration 2 leaked the scope past the loop and
// ate every genuine call after it. A header declaration reaches its control statement BEFORE any
// compound_statement (bodies ARE compound_statements, and C++ forbids a declaration as a braceless body),
// so "first ancestor of either kind wins" needs no field tracking — a body declaration hits the body block
// first, a header declaration the statement first. That same discrimination is what plainBlock reports.
inline ShadowScope enclosingShadowScope( TSNode n )
{
    TSNode p = ts_node_parent( n );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( kindIs( pt, "compound_statement" ) )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), true };
        }
        if(    kindIs( pt, "for_statement" ) || kindIs( pt, "for_range_loop" )
            || kindIs( pt, "if_statement" )  || kindIs( pt, "while_statement" )
            || kindIs( pt, "switch_statement" ) )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), false };
        }
        p = ts_node_parent( p );
    }
    return { 0u, 0u, false };
}

// r9 shadow fix round (A5, iteration 4): where an ordinary block declaration's names START shadowing.
// Iteration 2 started every span at the BLOCK's opening brace, which silently ate a genuine call written
// ABOVE the shadowing local (`key(); int key = 0;` lost the call — verifier attack4, a recall loss, not the
// disclosed over-suppression). THE DECLARATION POINT SHIPPED HERE IS THE END BYTE OF THE COMPLETE
// DECLARATOR, which is C++ [basic.scope.pdecl] exactly: the locus of a declarator is immediately after the
// complete declarator and before its initializer, and a structured binding's is immediately after its
// identifier-list — the outermost declarator's end byte is both. So `int a = probe(), probe = 0, b = probe;`
// keeps the call in a's initializer and suppresses b's read, and `int probe = probe;` suppresses its own
// initializer (which IS the new local, indeterminate value and all). The point itself is exact — a byte
// offset the grammar hands us, not an approximation — so what remains is the floor that was always there
// and is now simply visible ABOVE the point too: a pre-declaration site is only KEPT, never resolved, so if
// the name there denotes an OUTER local rather than the indexed symbol, --uses still name-matches it (the
// header's own "reference-name-based" disclosure). The one declaration this cannot narrow is a declarator
// tree emitShadowVarDecls refuses (`std::string key( tok );`, the most-vexing parse), which records no
// evidence at all and is the disclosed floor already.
// Applies ONLY to a plain block: a control-statement header declaration, and every whole-scope shape
// (definition/lambda/catch parameters, captures, range-for variables), is in scope from the START of its
// scope, so narrowing those would re-mint the false positives iterations 1-3 removed.
inline std::uint32_t shadowSpanStart( const ShadowScope& scope, TSNode completeDeclarator )
{
    if( !scope.plainBlock || ts_node_is_null( completeDeclarator ) )
    {
        return scope.start;
    }
    const std::uint32_t point = ts_node_end_byte( completeDeclarator );
    return point > scope.start ? point : scope.start;
}

// r9 shadow fix round (A5): every VARIABLE name a declarator declares → one VarDecl record each, carrying
// the declaring block's span. Handles the shapes the verifier refuted the first landing on:
//   * reference_declarator / parenthesized_declarator hold their inner declarator as an UNNAMED child
//     (no `declarator` field — same grammar fact fnDeclaratorVarName already works around), so a
//     field-only unwrap missed `const T& key` entirely — pass-by-const-ref, the most idiomatic C++
//     parameter shape;
//   * structured_binding_declarator (`auto& [key, w]`) declares SEVERAL names — one record per identifier;
//   * a plain function declarator still yields NOTHING (`void helper();` in a body and the most-vexing-
//     parse `Foo x();` declare a FUNCTION, whose calls must never be suppressed), while a
//     function_declarator whose inner is PARENTHESIZED is a fn-POINTER variable and stays a variable.
// Conservative by construction: an unrecognized shape captures nothing (under-suppression, the disclosed
// floor — e.g. the ctor-style most-vexing `std::string key( tok );`, which parses as a function decl).
inline void emitShadowVarDecls( std::uint32_t fileId, Lang lang, TSNode decl, std::string_view src,
                                BindSite site, std::vector<RawBind>& binds )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( kindIs( dt, "identifier" ) )
        {
            pushRawBind( fileId, lang, nodeTextOf( decl, src ), std::string{}, site, LocalBindKind::VarDecl, binds );
            return;
        }
        if( kindIs( dt, "structured_binding_declarator" ) )
        {
            const std::uint32_t cc = ts_node_named_child_count( decl );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode c = ts_node_named_child( decl, i );
                if( kindIs( ts_node_type( c ), "identifier" ) )
                {
                    pushRawBind( fileId, lang, nodeTextOf( c, src ), std::string{}, site, LocalBindKind::VarDecl, binds );
                }
            }
            return;
        }
        TSNode inner = fieldChild( decl, NodeField::Declarator );
        if( ts_node_is_null( inner )
            && ( kindIs( dt, "reference_declarator" ) || kindIs( dt, "parenthesized_declarator" ) )
            && ts_node_named_child_count( decl ) > 0 )
        {
            inner = ts_node_named_child( decl, 0 );   // the inner declarator is an UNNAMED child here
        }
        if( ts_node_is_null( inner ) )
        {
            return;
        }
        if( kindIs( dt, "function_declarator" ) && !kindIs( ts_node_type( inner ), "parenthesized_declarator" ) )
        {
            return;   // a FUNCTION's name, not a variable's
        }
        decl = inner;
    }
}

// one DECLARATOR → both records: the Rule-2 var→type binding and the r9 VarDecl shadow record(s). The two
// name reads stay separate on purpose — declaratorVarName descends into a function declarator (harmless
// for narrowing), emitShadowVarDecls refuses it (load-bearing for suppression).
inline void emitDeclBinds( std::uint32_t fileId, Lang lang, TSNode declNode, std::string_view src, std::string type,
                           BindSite site, std::vector<RawBind>& binds )
{
    const std::string_view var = declaratorVarName( declNode, src );
    if( var.empty() && !type.empty() )
    {
        // member-variable round (card A3): a REFERENCE local (`const Symbol& s = ing.symbols[ i ];`) is the one
        // typed declaration Rule 2 refuses (declaratorVarName cannot see through the unnamed reference child).
        // Recorded as a ParamType fact — the field use-site index's own kind — so `s.name` resolves there while
        // Rule 2's call narrowing (kind == Type) stays byte-identical.
        pushRawBind( fileId, lang, paramDeclaratorVarName( declNode, src ), std::move( type ), BindSite{ site.startByte, 0u, 0u }, LocalBindKind::ParamType, binds );
    }
    else
    {
        emitBind( fileId, lang, var, std::move( type ), site.startByte, binds );
    }
    emitShadowVarDecls( fileId, lang, declNode, src, site, binds );
}

// one parameter_list → VarDecl records for its named parameters, scoped to the owning BODY's span. Shared
// by the function-definition and lambda arms below (their parameter semantics are identical: names local
// to the body).
inline void emitShadowParamDecls( TSNode params, std::uint32_t fileId, Lang lang, std::string_view src,
                                  BindSite bodySite, std::vector<RawBind>& binds )
{
    const std::uint32_t cc = ts_node_child_count( params );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const TSNode p  = ts_node_child( params, i );
        const char*  pt = ts_node_type( p );
        if( !kindIs( pt, "parameter_declaration" ) && !kindIs( pt, "optional_parameter_declaration" ) )
        {
            continue;   // commas, `...`, attribute nodes — nothing declared
        }
        bodySite.startByte = ts_node_start_byte( p );
        const TSNode declarator = fieldChild( p, NodeField::Declarator );
        emitShadowVarDecls( fileId, lang, declarator, src, bodySite, binds );
        // member-variable round (card A3): the parameter's WRITTEN type as a ParamType record (`Counter& c` →
        // c:Counter), read by the field use-site index alone — see LocalBindKind::ParamType. `auto`, templated
        // and decltype types write nothing (writtenTypeOf's own refusal), and pushRawBind drops the record.
        pushRawBind( fileId, lang, paramDeclaratorVarName( declarator, src ), writtenTypeOf( fieldChild( p, NodeField::Type ), src ),
                     BindSite{ ts_node_start_byte( p ), 0u, 0u }, LocalBindKind::ParamType, binds );
    }
}

// A5 fix round: one LAMBDA's shadow-evidence names — parameters and capture-list names, all scoped to the
// lambda BODY's span. Lambdas are expressions, not definitions, so the definition arm below never sees
// them (the r9 sweep's A01 query is exactly a lambda parameter shadowing an indexed function). A simple
// capture (`[run]`) re-binds an outer VARIABLE (a function cannot be captured, so the name always denotes
// a variable) and an init-capture (`[trim = expr]`, node lambda_capture_initializer) introduces a NEW
// name — both are VarDecl evidence for the body span.
inline void captureLambdaShadowDecls( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                                      BindSite bodySite, std::vector<RawBind>& binds )
{
    const TSNode d = fieldChild( n, NodeField::Declarator );   // abstract_function_declarator
    if( !ts_node_is_null( d ) )
    {
        const TSNode params = fieldChild( d, NodeField::Parameters );
        if( !ts_node_is_null( params ) )
        {
            emitShadowParamDecls( params, fileId, lang, src, bodySite, binds );
        }
    }
    const TSNode caps = fieldChild( n, NodeField::Captures );   // lambda_capture_specifier
    if( ts_node_is_null( caps ) )
    {
        return;
    }
    // O(captures): a capture list's width is input-set like every other list — a comment run between two
    // captures is spliced into its child array (src/infra/tschildren.h), and 16 000 of them measured
    // 1.25 s of plain map on a one-line file before this became a cursor (arm B12).
    ChildCursor capsCursor( caps );
    forEachNamedChild( caps, capsCursor.cur, [ & ]( TSNode c )
    {
        const char* ct = ts_node_type( c );
        TSNode      ident {};
        if( kindIs( ct, "identifier" ) )
        {
            ident = c;   // simple capture `[run]` / `[&run]` (the `&` is an anonymous sibling)
        }
        else if( kindIs( ct, "lambda_capture_initializer" ) && ts_node_named_child_count( c ) > 0 )
        {
            const TSNode nm = ts_node_named_child( c, 0 );   // `[trim = expr]` — the FIRST named child is the introduced name
            if( kindIs( ts_node_type( nm ), "identifier" ) )
            {
                ident = nm;
            }
        }
        if( !ts_node_is_null( ident ) )
        {
            bodySite.startByte = ts_node_start_byte( c );
            pushRawBind( fileId, lang, nodeTextOf( ident, src ), std::string{}, bodySite, LocalBindKind::VarDecl, binds );
        }
        return true;
    } );
}

// a function DEFINITION's parameter_list, reached through its own declarator chain (`char* f(...)` /
// `T& f(...)` unwrap to the function_declarator). Null when the shape isn't a plain definition —
// walking only THIS chain (never bare parameter_declaration nodes) is what keeps a PROTOTYPE's
// parameters and a fn-pointer TYPE's parameter list out of shadow evidence.
inline TSNode fnDefParameterList( TSNode fnDef )
{
    TSNode decl = fieldChild( fnDef, NodeField::Declarator );
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ) && !kindIs( ts_node_type( decl ), "function_declarator" ); ++guard )
    {
        decl = fieldChild( decl, NodeField::Declarator );
    }
    if( ts_node_is_null( decl ) || !kindIs( ts_node_type( decl ), "function_declarator" ) )
    {
        return TSNode{};
    }
    return fieldChild( decl, NodeField::Parameters );
}

// r9 shadow suppression (A5 fix round): the local-declaring shapes that live OUTSIDE `declaration` nodes
// (the Rule-2 branch never sees them), dispatched on the caller's already-read node type `t`:
//   * a range-for's loop variable (`for( auto& s : v )`, incl. structured bindings) — scoped to the WHOLE
//     loop statement (iteration 3, unified with enclosingShadowScope's control-statement rule);
//   * a C++/ObjC function DEFINITION's named parameters — scoped to the definition BODY's span. Walking
//     only the definition node's own declarator chain (never bare parameter_declaration nodes) is what
//     keeps two non-scopes out: a PROTOTYPE's parameters (`void f(int run);` binds nothing anywhere) and a
//     fn-pointer type's parameter list (`void (*cb)(int run)` — those names are part of a TYPE, in no
//     scope at all);
//   * a LAMBDA's parameters and capture-list names — captureLambdaShadowDecls above;
//   * a CATCH clause's parameter — a local of its handler block (iteration 3, the noted 3b gap).
// Gates the language and node type ITSELF, so captureBindings calls it unconditionally — the shapes are
// disjoint from every branch of the Rule-2 chain there.
// Phase 4b (Rule 2c's shadow veto, docs/EVALS.md): a Python function DEFINITION's parameter NAMES as VarDecl
// evidence with an EMPTY span — the `{0,0}` "contains nothing" shape model.h's Binding documents — so they
// reach buildFieldNarrowTables' localNameSet (the veto Rules 2b/2c share: a parameter named like a class is a
// variable, not the class) and NOTHING else: the r9 shadow suppression tests span containment and is
// registered and measured for C++/ObjC only, so the Python call graph moves through Rule 2c alone. `self`
// and `cls` are recorded like any other name (no class is spelled that way; a special case would be a
// second rule to keep in step). Plain, typed, defaulted and splat parameters; tuple patterns bind nothing.
inline void capturePythonParamShadowDecls( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawBind>& binds )
{
    const TSNode params = fieldChild( n, NodeField::Parameters );
    if( ts_node_is_null( params ) )
    {
        return;
    }
    const std::uint32_t cc = ts_node_child_count( params );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const TSNode p  = ts_node_child( params, i );
        const char*  pt = ts_node_type( p );
        TSNode       ident{};
        if( kindIs( pt, "identifier" ) )
        {
            ident = p;
        }
        else if( kindIs( pt, "default_parameter" ) || kindIs( pt, "typed_default_parameter" ) )
        {
            ident = fieldChild( p, NodeField::Name );
        }
        else if( kindIs( pt, "typed_parameter" ) || kindIs( pt, "list_splat_pattern" ) || kindIs( pt, "dictionary_splat_pattern" ) )
        {
            ident = ts_node_named_child( p, 0 );
        }
        if( ts_node_is_null( ident ) || !kindIs( ts_node_type( ident ), "identifier" ) )
        {
            continue;   // commas, separators, tuple patterns — nothing this veto can name
        }
        pushRawBind( fileId, lang, nodeTextOf( ident, src ), std::string{}, BindSite{ ts_node_start_byte( p ), 0u, 0u }, LocalBindKind::VarDecl, binds );
    }
}

inline void captureShadowScopeDecls( TSNode n, const char* t, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawBind>& binds )
{
    if( lang == Lang::Python )
    {
        if( kindIs( t, "function_definition" ) )
        {
            capturePythonParamShadowDecls( n, fileId, lang, src, binds );   // Phase 4b: veto evidence only (empty span)
        }
        return;
    }
    if( lang != Lang::Cpp && lang != Lang::ObjC )
    {
        return;
    }
    const bool isRangeFor = kindIs( t, "for_range_loop" );
    const bool isLambda   = !isRangeFor && kindIs( t, "lambda_expression" );
    const bool isCatch    = !isRangeFor && !isLambda && kindIs( t, "catch_clause" );
    const bool isFnDef    = !isRangeFor && !isLambda && !isCatch && kindIs( t, "function_definition" );
    if( !isRangeFor && !isLambda && !isCatch && !isFnDef )
    {
        return;   // every other node type declares nothing this capture owns
    }
    const TSNode body = fieldChild( n, NodeField::Body );
    if( ts_node_is_null( body ) )
    {
        return;   // a body-less shape scopes nothing (declaration-only lambda/definition never parses so)
    }
    const BindSite bodySite{ ts_node_start_byte( n ), ts_node_start_byte( body ), ts_node_end_byte( body ) };
    if( isRangeFor )
    {
        // iteration 3, unified with enclosingShadowScope's control-statement rule: the loop variable scopes
        // to the WHOLE for_range_loop statement (its own span), not merely the body.
        const BindSite loopSite{ ts_node_start_byte( n ), ts_node_start_byte( n ), ts_node_end_byte( n ) };
        const TSNode   loopDeclarator = fieldChild( n, NodeField::Declarator );
        emitShadowVarDecls( fileId, lang, loopDeclarator, src, loopSite, binds );
        // member-variable round (card A3): the loop variable's WRITTEN type (`for( const Symbol& s : v )` →
        // s:Symbol) as a ParamType record for the field use-site index — the single most common typed
        // receiver shape in this repo's own source (`s.name`), and `auto` writes nothing, as for parameters.
        pushRawBind( fileId, lang, paramDeclaratorVarName( loopDeclarator, src ), writtenTypeOf( fieldChild( n, NodeField::Type ), src ),
                     BindSite{ ts_node_start_byte( n ), 0u, 0u }, LocalBindKind::ParamType, binds );
        return;
    }
    if( isLambda )
    {
        captureLambdaShadowDecls( n, fileId, lang, src, bodySite, binds );
        return;
    }
    // a catch parameter is a local of its HANDLER block (iteration 3, the noted 3b gap) — its
    // parameter_list is a direct field; a definition's sits behind the declarator chain
    // (fnDefParameterList above), which is what keeps prototypes and fn-pointer TYPE params out.
    const TSNode params = isCatch ? fieldChild( n, NodeField::Parameters ) : fnDefParameterList( n );
    if( !ts_node_is_null( params ) )
    {
        emitShadowParamDecls( params, fileId, lang, src, bodySite, binds );
    }
}

// emit one L3 var→function RawBind (kind FnDecl/FnAssign) — emitBind's record shape with the kind stamped
// after the push, so the two emitters share ONE body instead of cloning it.
inline void emitFnBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string target,
                        std::uint32_t startByte, LocalBindKind kind, std::vector<RawBind>& binds )
{
    const std::size_t before = binds.size();
    emitBind( fileId, lang, var, std::move( target ), startByte, binds );
    if( binds.size() > before )
    {
        binds.back().kind = kind;
    }
}

// L3 capture over one C-family `declaration` node: one FnDecl record per init_declarator whose RHS names a
// function (`&alpha` / `beta` / a lambda). `&name` and lambdas are self-evidencing and emit at once;
// a BARE-IDENTIFIER initializer is the one shape a fn-pointer bind shares with a plain value copy, so it
// goes to the VALUE-INITIALIZATION NOISE GATE below (`pending`) unless the declarator itself spells a fn
// pointer, which settles it on the spot.
// A reference declarator (`H& r = fn;`) emits NO positive and clobbers the bound-to var (A5 escape guard).
inline void captureFnBindDecl( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                               std::vector<RawBind>& fnPos, std::vector<FnBindClobber>& fnUnk,
                               std::vector<PendingFnBindDecl>& pending )
{
    const TSNode typeNode = fieldChild( n, NodeField::Type );
    std::string  writtenType;
    const bool   concrete = concreteWrittenType( typeNode, src, writtenType );
    // O(children), on the cursor's O(1) field name — see fnPtrAliasName above and arm B7.
    ChildCursor cursor( n );
    forEachChild( n, cursor.cur, [ & ]( TSNode c )
    {
        const char* fname = ts_tree_cursor_current_field_name( &cursor.cur );
        if( fname == nullptr || !kindIs( fname, "declarator" ) )
        {
            return true;
        }
        if( !kindIs( ts_node_type( c ), "init_declarator" ) )
        {
            return true;   // no initializer → no binding fact here (a later assignment carries its own)
        }
        const auto [ var, sawFnDecl, sawPtrDecl, sawRef ] = fnDeclaratorShape( fieldChild( c, NodeField::Declarator ), src );
        const TSNode valueNode = fieldChild( c, NodeField::Value );
        if( sawRef )
        {
            // A5 escape guard: `H& r = fn;` / `auto& r = fn;` ALIASES fn — a write through r retargets fn
            // invisibly, so the bound-to variable is clobbered (toward tombstone, never toward resolve) and
            // the alias itself gets NO positive (its target can change under it the same way).
            if( !ts_node_is_null( valueNode ) && kindIs( ts_node_type( valueNode ), "identifier" ) )
            {
                const std::string_view aliased = nodeTextOf( valueNode, src );
                if( !aliased.empty() )
                {
                    fnUnk.push_back( { std::string( aliased ), ts_node_start_byte( n ) } );
                }
            }
            return true;
        }
        bool bareIdent = false;
        std::string target = fnBindTargetOf( valueNode, src, bareIdent );
        if( bareIdent && !target.empty() && !( sawFnDecl && sawPtrDecl ) )
        {
            // the declarator does not itself spell a fn pointer, so only the WRITTEN TYPE can tell a bind
            // from a copy — and that answer needs the file's complete alias table. Hold it.
            pending.push_back( { std::string( var ), std::move( target ), writtenType, ts_node_start_byte( n ), concrete } );
            return true;
        }
        emitFnBind( fileId, lang, var, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnDecl, fnPos );
        return true;
    } );
}

// A5 escape guard over one `pointer_expression`: `&fn` ANYWHERE makes the variable mutable through the
// pointer (`indirect_mutate(&fn)` retargets it behind the resolver's back), so any address-of over a bare
// identifier records a CLOBBER for that identifier — toward tombstone, never toward resolve. A by-value use
// (`takes_fn(fn)`, `other = fn`) copies the pointer and cannot mutate the variable, so it does NOT clobber.
// The `&alpha` inside a positive binding RHS also lands here (clobbering the FUNCTION's name as a "var") —
// harmless-conservative: it only matters if a same-named variable holds a binding in this file, and then
// refusing to resolve it is the safe side. Dereferences (`*p`) are excluded by the operator check.
inline void captureFnBindEscape( TSNode n, std::string_view src, std::vector<FnBindClobber>& fnUnk )
{
    const TSNode op = ts_node_child( n, 0 );
    if( ts_node_is_null( op ) || !kindIs( ts_node_type( op ), "&" ) )
    {
        return;
    }
    const TSNode idn = fieldChild( n, NodeField::Argument );
    if( ts_node_is_null( idn ) || !kindIs( ts_node_type( idn ), "identifier" ) )
    {
        return;
    }
    const std::string_view var = nodeTextOf( idn, src );
    if( !var.empty() )
    {
        fnUnk.push_back( { std::string( var ), ts_node_start_byte( n ) } );
    }
}

// L3 capture over one C-family `assignment_expression`: a recognizable RHS emits an FnAssign record; any
// other RHS on a bare-identifier LHS (`fn = getHandler()`, `fn = nullptr`, `n += 1`) records a CLOBBER
// candidate, emitted as a tombstone at the end of the walk IF the var has a fn binding in the same file.
// A BARE-IDENTIFIER RHS (`fn = beta;`) is neither yet: it is the one shape a plain value copy shares with a
// genuine fn-pointer rebind, and the assignment node carries no type to tell them apart — so it is held in
// `pending` for the end-of-walk value-assignment noise gate above, which asks the file's own declarations.
// The second branch decodes the C++-grammar MIS-PARSE of a raw fn-pointer declaration (`void (*fn)() =
// &alpha;` — see misparsedFnPtrDeclVar): the shape itself proves a fn-pointer declarator, so a
// bare-identifier RHS is captured immediately there — the "type" IS the evidence, no gate needed.
inline void captureFnBindAssign( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                                 std::vector<RawBind>& fnPos, std::vector<FnBindClobber>& fnUnk,
                                 std::vector<PendingFnBindAssign>& pending )
{
    const TSNode lhs = fieldChild( n, NodeField::Left );
    const TSNode rhs = fieldChild( n, NodeField::Right );
    if( !ts_node_is_null( lhs ) && kindIs( ts_node_type( lhs ), "identifier" ) )
    {
        const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
        if( a <= b && b <= src.size() )
        {
            const std::string_view var = src.substr( a, b - a );
            bool bareIdent = false;
            std::string target = fnBindTargetOf( rhs, src, bareIdent );
            if( target.empty() )
            {
                fnUnk.push_back( { std::string( var ), ts_node_start_byte( n ) } );
            }
            else if( bareIdent )
            {
                pending.push_back( { std::string( var ), std::move( target ), ts_node_start_byte( n ) } );
            }
            else
            {
                emitFnBind( fileId, lang, var, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnAssign, fnPos );
            }
        }
    }
    else if( const std::string_view dvar = misparsedFnPtrDeclVar( lhs, src ); !dvar.empty() )
    {
        bool bareIdent = false;
        std::string target = fnBindTargetOf( rhs, src, bareIdent );
        if( !target.empty() )
        {
            emitFnBind( fileId, lang, dvar, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnDecl, fnPos );
        }
        else
        {
            fnUnk.push_back( { std::string( dvar ), ts_node_start_byte( n ) } );
        }
    }
}

// decide every bare-identifier assignment the walk held back, against the file's COMPLETE declaration
// evidence. A name the file proved to be a VALUE variable where the assignment sits records NOTHING — not a
// positive, and deliberately not a clobber either: a clobber is a statement ABOUT a function pointer ("this
// one is no longer trustworthy"), and the end-of-walk sweep promotes it to a real FnAssign tombstone as
// soon as any same-named var in the file holds a binding. That tombstone reads as a binding to every
// consumer — it re-vetoed the very shadow suppression this gate exists to restore. A copy into a string is
// evidence in NEITHER direction. Everything else mints its FnAssign exactly as it did before the gate.
inline void resolvePendingFnBindAssigns( std::uint32_t fileId, Lang lang, FnBindGateState& gate, std::vector<RawBind>& fnPos )
{
    for( PendingFnBindAssign& p : gate.pending )
    {
        if( !fnBindProvenValueVar( p.var, p.startByte, gate.facts, gate.aliases ) )
        {
            emitFnBind( fileId, lang, p.var, std::move( p.target ), p.startByte, LocalBindKind::FnAssign, fnPos );
        }
    }
}

// ── L3 VALUE-INITIALIZATION NOISE GATE (r9 fix round, DECLARATION arm) ───────────────────────────────
// The sibling gate above answers "what is this VARIABLE?" from the file's declarations because an
// assignment node carries no type. A declaration carries one, so this arm asks the stronger question
// directly of the node in front of it: does the WRITTEN TYPE prove a value?
//   * a CONCRETE type that is no fn-pointer alias — `std::string tag = zzz;`, `Box b = other;`,
//     `int a = b;` — is a copy. No binding. Before this gate only the PRIMITIVE half of that was caught,
//     so a CLASS-typed copy minted an FnDecl, and shadowSuppressedSite (model.h) VETOES local-shadow
//     suppression for any name carrying an L3 binding — the local handed its every read/write site back to
//     the function it shadows. That is the same harm, and the same mechanism, as the assignment arm's.
//   * a fn-pointer DECLARATOR (`void (*fp)() = handler;`) never reaches here at all: the shape is its own
//     evidence and captureFnBindDecl emits it on the spot.
//   * a same-file fn-pointer ALIAS (`typedef void (*H)(); H fp = beta;`) mints — the alias table is why
//     these records are deferred to the end of the walk rather than judged where they are written.
//   * everything else is UNKNOWN and unknown MINTS: `auto fp = f;` (the idiomatic form), `decltype(...)`,
//     and any template/dependent type. Refusing to guess is what keeps this gate from costing recall.
// DISCLOSED BLIND SPOT, pinned by test/fnptrcheck.sh arm (t): the alias evidence is SAME-FILE, so a
// `typedef void (*H)();` living in a HEADER leaves `H fp = beta;` indistinguishable from a value copy and
// its edge is gated away. It cost ZERO edges on the two corpora this round measured (this repo, 1093 files
// / 10771 edges, full map byte-identical; a 2376-file ObjC++ tree, 39741 edges, every callee row identical
// and only `unresolved=` moving 2577 → 2509) — but that is a measurement, not a proof. Widening the alias
// evidence corpus-wide is the fix if a corpus ever pays for it.
inline void resolvePendingFnBindDecls( std::uint32_t fileId, Lang lang, FnBindGateState& gate, std::vector<RawBind>& fnPos )
{
    for( PendingFnBindDecl& p : gate.pendingDecl )
    {
        const bool aliasTyped  = !p.typeName.empty() && gate.aliases.find( p.typeName ) != gate.aliases.end();
        const bool provenValue = p.concreteType && !aliasTyped;
        if( !provenValue )
        {
            emitFnBind( fileId, lang, p.var, std::move( p.target ), p.startByte, LocalBindKind::FnDecl, fnPos );
        }
    }
}

// P2-D Rule 2 local var→type bindings + the L3 fn-pointer capture. One visitor on the shared pre-order
// stream (streamSideCaptures below) — the pass used to own an identical walk of its own, which is what the
// fusion removed. Its state outlives a single node (the L3 clobber sweep needs the whole file's positives),
// so it rides in a context the driver holds by reference; bindsFinalize spends it when the stream ends.
struct BindCtx
{
    std::uint32_t              fileId = 0;
    Lang                       lang {};
    std::string_view           src;
    std::vector<RawBind>*      binds = nullptr;

    // L3 fn-pointer buffers. Positives collect here (not straight into binds) so the end-of-walk clobber
    // sweep can ask "does this var have a fn binding in this file?" — a clobbering assignment
    // (`fn = getHandler()`) matters only then, which keeps a fn-binding-free file contributing ZERO new
    // records (the whole feature inert there).
    std::vector<RawBind>       fnPos;
    std::vector<FnBindClobber> fnUnk;
    FnBindGateState            fnGate;      // value-assignment noise-gate evidence — filled by the stream, spent at the end
    bool                       cFamilyFn = false;
};

void bindsVisitNode( BindCtx& cx, TSNode n, const char* t )
{
    // The body below is the pass's own node step, unchanged; these aliases keep it reading against the
    // same names it always had rather than sprinkling `cx.` through 150 lines of grammar branches.
    FUSEPROBE_BUMP( kBinds );
    const std::uint32_t         fileId    = cx.fileId;
    const Lang                  lang      = cx.lang;
    const std::string_view      src       = cx.src;
    std::vector<RawBind>&       binds     = *cx.binds;
    std::vector<RawBind>&       fnPos     = cx.fnPos;
    std::vector<FnBindClobber>& fnUnk     = cx.fnUnk;
    FnBindGateState&            fnGate    = cx.fnGate;
    const bool                  cFamilyFn = cx.cFamilyFn;

    // C++/ObjC: `Foo x;` · `Foo* x;` · `Foo x = Foo();` · `auto x = Foo();`
    if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && kindIs( t, "declaration" ) )
    {
        const TSNode typeNode = fieldChild( n, NodeField::Type );
        std::string  written  = writtenTypeOf( typeNode, src );
        // A5 fix round: the declared names shadow within their enclosing block (or, for a control-statement
        // header declaration, that whole statement) — one parent walk per declaration node, shared by every
        // declarator child below; each declarator then contributes its own declaration POINT as the span's
        // start (shadowSpanStart).
        const ShadowScope scope = enclosingShadowScope( n );
        // a `declaration` can declare several variables (`Foo a, b;`) → one binding per declarator child.
        // O(children), not O(children³): this loop used to ask for `ts_node_child( n, i )` AND
        // `ts_node_field_name_for_child( n, i )` twice, and all three restart tree-sitter's child iterator at
        // the first child (src/infra/tschildren.h). A declaration's width is input-set — every comment between
        // the type and the declarator is a direct child — and 16 000 of them measured 77x the identical flood
        // beside the declaration (test/childwalkscalecheck.sh, arm B7, which also records why the cursor's
        // O(1) `ts_tree_cursor_current_field_name` is the same answer: node.c:689 vs tree_cursor.c:657).
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char* field = ts_tree_cursor_current_field_name( &cursor.cur );
            if( field == nullptr || !kindIs( field, "declarator" ) ) { return true; }
            const char* ct = ts_node_type( c );
            // `init_declarator`: name lives in its `declarator`, the RHS in its `value` (for auto inference).
            // emitDeclBinds also records the r9 VarDecl shadow fact for the declared NAME regardless of type
            // resolvability (`int run = 0;` binds no type — writtenTypeOf refuses primitives — yet the local
            // exists and shadows).
            if( kindIs( ct, "init_declarator" ) )
            {
                const TSNode declarator = fieldChild( c, NodeField::Declarator );
                std::string  type       = written.empty() ? ctorTypeOf( fieldChild( c, NodeField::Value ), src ) : written;
                emitDeclBinds( fileId, lang, declarator, src, std::move( type ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, declarator ), scope.end }, binds );
            }
            else   // plain declarator (identifier / pointer_declarator / reference_declarator), no initializer
            {
                emitDeclBinds( fileId, lang, c, src, std::string( written ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, c ), scope.end }, binds );
            }
            return true;
        } );
    }
    // C++ `x = Foo();` (re-assignment to a constructor) — assignment_expression inside an expression_statement.
    else if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && kindIs( t, "assignment_expression" ) )
    {
        const TSNode lhs = fieldChild( n, NodeField::Left );
        const TSNode rhs = fieldChild( n, NodeField::Right );
        if( !ts_node_is_null( lhs ) && kindIs( ts_node_type( lhs ), "identifier" ) )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                emitBind( fileId, lang, src.substr( a, b - a ), ctorTypeOf( rhs, src ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // Python `x = Foo()` — assignment with a bare-identifier LHS and a constructor-call RHS.
    else if( lang == Lang::Python && kindIs( t, "assignment" ) )
    {
        const TSNode lhs = fieldChild( n, NodeField::Left );
        const TSNode rhs = fieldChild( n, NodeField::Right );
        if( !ts_node_is_null( lhs ) && kindIs( ts_node_type( lhs ), "identifier" ) )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                // Python RHS constructor is a `call` node (not `call_expression`); reuse finalSegment on its callee.
                std::string type;
                if( !ts_node_is_null( rhs ) && kindIs( ts_node_type( rhs ), "call" ) )
                {
                    const TSNode fn = fieldChild( rhs, NodeField::Function );
                    if( !ts_node_is_null( fn ) && kindIs( ts_node_type( fn ), "identifier" ) )
                    {
                        const std::uint32_t fa = ts_node_start_byte( fn ), fb = ts_node_end_byte( fn );
                        if( fa <= fb && fb <= src.size() )
                        {
                            type = finalSegment( src.substr( fa, fb - fa ) );
                        }
                    }
                }
                emitBind( fileId, lang, src.substr( a, b - a ), std::move( type ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // TypeScript `const x = new Foo();` · `let y: Bar = ...;` — variable_declarator.
    else if( lang == Lang::TypeScript && kindIs( t, "variable_declarator" ) )
    {
        const TSNode nameNode = fieldChild( n, NodeField::Name );
        if( !ts_node_is_null( nameNode ) && kindIs( ts_node_type( nameNode ), "identifier" ) )
        {
            const std::uint32_t a = ts_node_start_byte( nameNode ), b = ts_node_end_byte( nameNode );
            if( a <= b && b <= src.size() )
            {
                // prefer the `: Type` annotation; else infer from a `new Foo()` / `Foo()` initializer.
                std::string type;
                const TSNode ann = fieldChild( n, NodeField::Type );   // type_annotation
                if( !ts_node_is_null( ann ) )
                {
                    // O(children): the scan stops at the first type_identifier, but nothing bounds how many
                    // comments precede one — `let x: /* … */ Foo` splices each into the annotation's child list.
                    ChildCursor annCursor( ann );
                    forEachChild( ann, annCursor.cur, [ & ]( TSNode c )
                    {   if( !kindIs( ts_node_type( c ), "type_identifier" ) ) { return true; }
                        const std::uint32_t ta = ts_node_start_byte( c ), tb = ts_node_end_byte( c );
                        if( ta <= tb && tb <= src.size() ) { type = finalSegment( src.substr( ta, tb - ta ) ); }
                        return false; } );   // the indexed loop's `break`: the FIRST type_identifier wins
                }
                if( type.empty() )
                {
                    type = ctorTypeOf( fieldChild( n, NodeField::Value ), src );
                }
                emitBind( fileId, lang, src.substr( a, b - a ), std::move( type ), ts_node_start_byte( n ), binds );
            }
        }
    }

    // r9 shadow suppression: the local-declaring shapes OUTSIDE `declaration` nodes — a function
    // DEFINITION's named parameters and a range-for's loop variable. Unconditional (the helper gates
    // language and node type itself); disjoint from every branch of the Rule-2 chain above.
    captureShadowScopeDecls( n, t, fileId, lang, src, binds );

    // ── L3 fn-pointer/callback capture (C/C++/ObjC) — a SEPARATE if (not part of the Rule-2 chain above):
    // the same `declaration` node can carry BOTH a Rule-2 var→type fact and a var→function fact
    // (`H fnPtr = beta;` emits fnPtr:H for receiver narrowing AND fnPtr→beta for call resolution). ──
    if( cFamilyFn && kindIs( t, "declaration" ) )
    {
        captureFnBindDecl( n, fileId, lang, src, fnPos, fnUnk, fnGate.pendingDecl );
    }
    else if( cFamilyFn && kindIs( t, "assignment_expression" ) )
    {
        captureFnBindAssign( n, fileId, lang, src, fnPos, fnUnk, fnGate.pending );
    }
    else if( cFamilyFn && kindIs( t, "pointer_expression" ) )
    {
        captureFnBindEscape( n, src, fnUnk );   // A5: `&fn` anywhere clobbers the variable (escape guard)
    }
    collectFnBindGateEvidence( n, t, src, cFamilyFn, fnGate );   // never an `else if` — see the helper's note
}

// End-of-file step for the bindings pass: the two noise gates and the L3 clobber sweep. Split out of the
// walk (it was the tail of captureBindings) so the shared stream can run it once the last node is visited.
void bindsFinalize( BindCtx& cx )
{
    const std::uint32_t         fileId = cx.fileId;
    const Lang                  lang   = cx.lang;
    std::vector<RawBind>&       binds  = *cx.binds;
    std::vector<RawBind>&       fnPos  = cx.fnPos;
    std::vector<FnBindClobber>& fnUnk  = cx.fnUnk;
    FnBindGateState&            fnGate = cx.fnGate;

    resolvePendingFnBindDecls  ( fileId, lang, fnGate, fnPos );   // both noise gates — BEFORE the sweep, which needs
    resolvePendingFnBindAssigns( fileId, lang, fnGate, fnPos );   // fnPos final (its var scan is a membership test,
                                                                  // so the deferral cannot change a clobber verdict)

    // ── L3 clobber sweep + merge. A clobbering assignment forces the tombstone (kFnBindClobberTarget) so a
    // stale earlier binding can never win (`void (*fn)() = &alpha; fn = getHandler(); fn();` → NO edge) —
    // but only for a var that HAS a recognizable fn binding somewhere in this file, an over-approximation
    // of "same scope" that errs toward the tombstone, never toward a resolve. posCount is captured BEFORE
    // the emits below so the sweep scans only the walk's own positives.
    if( !fnPos.empty() )
    {
        const std::size_t posCount = fnPos.size();
        for( const FnBindClobber& u : fnUnk )
        {
            bool hasPos = false;
            for( std::size_t p = 0; p < posCount; ++p )
            {
                if( fnPos[p].var == u.var )
                {
                    hasPos = true;
                    break;
                }
            }
            if( hasPos )
            {
                emitFnBind( fileId, lang, u.var, std::string( kFnBindClobberTarget ), u.startByte, LocalBindKind::FnAssign, binds );
            }
        }
        for( RawBind& p : fnPos )
        {
            binds.push_back( std::move( p ) );
        }
    }
}
}   // namespace — ingest_binds.h section of ingest.cpp

}   // namespace rw
