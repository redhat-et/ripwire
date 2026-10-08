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
// FieldOfThis / FieldOfVar; both "" for None / ThisObj. `viaArrow`: the call's own member access was written
// `->` (C++/ObjC) — set by receiverOf only, which is the one caller that holds that access.
struct RecvShape
{
    RecvKind    kind = RecvKind::None;
    std::string var;
    std::string field;
    bool        viaArrow = false;
    bool        member = false;   // FE-A: Go/JS/TS/Rust — the callee is a member access's field (model.h Reference::memberCall);
                                  //   FE-B adds Java, Kotlin, C# and Swift, whose member calls recorded no shape at all
    std::string root;             // FE-A: that access's receiver-chain root identifier, "" when not an identifier
    std::string path;             // FE-B: the member names between root and the callee, '.'-joined (model.h Reference::memberPath)
    std::string ctor;             // FE-B: the class a constructed receiver names (model.h Reference::memberCtor)
};

// FE-A (model.h Reference::memberRoot): the ROOT identifier of a Go/JS/TS/Rust receiver chain — `crypto` for
// `crypto.subtle`, `this` for `this.a`, the package alias for `pkg.F`. Walks only member accesses (`a.b.c` →
// `a`); any other receiver node (a call, `new X()`, a subscript, a literal, a parenthesized expression) has no
// root identifier and answers "". `self` in Rust and `this` in JS answer their own spelling, so a consumer can
// tell them from a package or a global object. Bounded by the chain's depth, which the tree bounds.
inline std::string memberChainRoot( TSNode recv, std::string_view src )
{
    TSNode node = recv;
    for( int depth = 0; depth < 64 && !ts_node_is_null( node ); ++depth )
    {
        const char* t = ts_node_type( node );
        if( kindIs( t, "identifier" ) || kindIs( t, "this" ) || kindIs( t, "self" ) || kindIs( t, "package_identifier" ) )
        {
            return std::string( pattern::nodeText( node, src ) );
        }
        if( kindIs( t, "member_expression" ) )
        {
            node = fieldChild( node, NodeField::Object );
        }
        else if( kindIs( t, "selector_expression" ) )
        {
            node = fieldChild( node, NodeField::Operand );
        }
        else if( kindIs( t, "field_expression" ) )
        {
            node = fieldChild( node, NodeField::Value );
        }
        else
        {
            return {};
        }
    }
    return {};
}

// FE-B (model.h Reference::memberPath / memberCtor): one receiver chain, walked from the call's immediate receiver down to
// its root, for the languages whose member calls carry no RecvKind (JS/TS, Go, Java, Kotlin, C#, Swift). `root` keeps
// memberChainRoot's answer for JS/TS and Go (FE-A reads it) and adds `super` (JS/TS/Java/Kotlin/Swift; C#'s `base`),
// `this`/`self` spellings of the other languages, which FE-A never sees. `path` collects the member names passed on
// the way down, in source order; `ctor` is the class a constructed receiver names (`new X( … )`, Go `X{ … }` or
// `&X{ … }`), final segment, with root "". Any other node (a call, a subscript, a literal) ends the walk with root ""
// and an empty path. Bounded by the chain's depth like memberChainRoot.
struct MemberChain
{
    std::string root;
    std::string path;
    std::string ctor;
};

inline std::string_view finalTypeSegment( TSNode typeNode, std::string_view src )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( typeNode ); ++guard )
    {
        const char* t = ts_node_type( typeNode );
        if( kindIs( t, "type_identifier" ) || kindIs( t, "identifier" ) || kindIs( t, "simple_identifier" ) )
        {
            return pattern::nodeText( typeNode, src );
        }
        if( kindIs( t, "qualified_type" ) )                  // Go `pkg.T`
        {
            typeNode = fieldChild( typeNode, NodeField::Name );
        }
        else if( kindIs( t, "pointer_type" ) || kindIs( t, "generic_type" ) || kindIs( t, "parenthesized_type" ) )
        {
            typeNode = ts_node_named_child_count( typeNode ) > 0 ? ts_node_named_child( typeNode, ts_node_named_child_count( typeNode ) - 1 ) : TSNode{};
            if( !ts_node_is_null( typeNode ) && kindIs( t, "generic_type" ) )
            {
                typeNode = ts_node_named_child( ts_node_parent( typeNode ), 0 );   // `Foo<T>`: the name, never the argument list
            }
        }
        else if( kindIs( t, "member_expression" ) || kindIs( t, "scoped_type_identifier" ) || kindIs( t, "nested_identifier" ) )
        {
            const std::uint32_t n = ts_node_named_child_count( typeNode );
            typeNode = n > 0 ? ts_node_named_child( typeNode, n - 1 ) : TSNode{};
            if( !ts_node_is_null( typeNode ) && kindIs( ts_node_type( typeNode ), "property_identifier" ) )
            {
                return pattern::nodeText( typeNode, src );
            }
        }
        else
        {
            return {};
        }
    }
    return {};
}

// the class a constructed receiver names, final segment; "" when `node` constructs nothing this rule reads
inline std::string_view constructedClass( TSNode node, Lang lang, std::string_view src )
{
    const char* t = ts_node_type( node );
    if( ( lang == Lang::JavaScript || lang == Lang::TypeScript ) && kindIs( t, "new_expression" ) )
    {
        return finalTypeSegment( fieldChild( node, NodeField::Constructor ), src );
    }
    if( ( lang == Lang::Java || lang == Lang::CSharp ) && kindIs( t, "object_creation_expression" ) )
    {
        return finalTypeSegment( fieldChild( node, NodeField::Type ), src );
    }
    if( lang == Lang::Go && kindIs( t, "composite_literal" ) )
    {
        return finalTypeSegment( fieldChild( node, NodeField::Type ), src );
    }
    if( lang == Lang::Go && kindIs( t, "unary_expression" ) && ts_node_named_child_count( node ) == 1 )
    {
        const TSNode operand = ts_node_named_child( node, 0 );
        return kindIs( ts_node_type( operand ), "composite_literal" ) ? finalTypeSegment( fieldChild( operand, NodeField::Type ), src ) : std::string_view{};
    }
    return {};
}

inline MemberChain memberChainOf( TSNode recv, Lang lang, std::string_view src )
{
    MemberChain out;
    std::vector<std::string_view> names;   // collected receiver-first (innermost member last), reversed below
    TSNode node = recv;
    for( int depth = 0; depth < 64 && !ts_node_is_null( node ); ++depth )
    {
        const char* t = ts_node_type( node );
        if( kindIs( t, "parenthesized_expression" ) && ts_node_named_child_count( node ) == 1 )
        {
            node = ts_node_named_child( node, 0 );
            continue;
        }
        if( kindIs( t, "identifier" ) || kindIs( t, "this" ) || kindIs( t, "self" ) || kindIs( t, "package_identifier" ) || kindIs( t, "super" )
            || kindIs( t, "simple_identifier" ) || kindIs( t, "this_expression" ) || kindIs( t, "super_expression" ) || kindIs( t, "self_expression" )
            || kindIs( t, "base_expression" ) )
        {
            out.root = std::string( pattern::nodeText( node, src ) );
            break;
        }
        TSNode next{};
        TSNode name{};
        if( kindIs( t, "member_expression" ) )                              // JS/TS
        {
            next = fieldChild( node, NodeField::Object );   name = fieldChild( node, NodeField::Property );
        }
        else if( kindIs( t, "selector_expression" ) )                       // Go
        {
            next = fieldChild( node, NodeField::Operand );  name = fieldChild( node, NodeField::Field );
        }
        else if( kindIs( t, "field_access" ) )                              // Java
        {
            next = fieldChild( node, NodeField::Object );   name = fieldChild( node, NodeField::Field );
        }
        else if( kindIs( t, "member_access_expression" ) )                  // C#
        {
            next = fieldChild( node, NodeField::Expression );  name = fieldChild( node, NodeField::Name );
        }
        else if( kindIs( t, "navigation_expression" ) && ts_node_named_child_count( node ) == 2 )   // Kotlin / Swift
        {
            next = ts_node_named_child( node, 0 );
            const TSNode suffix = ts_node_named_child( node, 1 );
            name = ts_node_named_child_count( suffix ) > 0 ? ts_node_named_child( suffix, ts_node_named_child_count( suffix ) - 1 ) : TSNode{};
        }
        else
        {
            const std::string_view ctor = constructedClass( node, lang, src );
            if( ctor.empty() )
            {
                return MemberChain{};   // a call, subscript or literal: no root identifier and no path
            }
            out.ctor = std::string( ctor );
            break;
        }
        if( ts_node_is_null( next ) || ts_node_is_null( name ) )
        {
            return MemberChain{};
        }
        names.push_back( pattern::nodeText( name, src ) );
        node = next;
    }
    if( out.root.empty() && out.ctor.empty() )
    {
        return MemberChain{};
    }
    for( auto it = names.rbegin(); it != names.rend(); ++it )
    {
        if( !out.path.empty() )
        {
            out.path.push_back( '.' );
        }
        out.path.append( *it );
    }
    return out;
}

// FE-A: the member-access node kind and its receiver field for the languages whose receiverOf records no shape (Go, JS/TS,
// Rust; and C, whose only member call is a call through a function-pointer field).
inline TSNode memberOnlyReceiver( TSNode parent, Lang lang ) noexcept
{
    const char* t = ts_node_type( parent );
    if( ( lang == Lang::TypeScript || lang == Lang::JavaScript ) && kindIs( t, "member_expression" ) )
    {
        return fieldChild( parent, NodeField::Object );
    }
    if( lang == Lang::Go && kindIs( t, "selector_expression" ) )
    {
        return fieldChild( parent, NodeField::Operand );
    }
    if( lang == Lang::Rust && kindIs( t, "field_expression" ) )
    {
        return fieldChild( parent, NodeField::Value );
    }
    if( lang == Lang::Rust && kindIs( t, "scoped_identifier" ) )
    {
        // a PATH call: `Type::f()`, `Self::f()`, `<T as Trait>::f()` — never bare, even when rustQualifierOf leaves the
        // qualifier empty (the UFCS cast form), so FE-A must not read it as a receiverless call
        return fieldChild( parent, NodeField::Path );
    }
    if( lang == Lang::C && kindIs( t, "field_expression" ) )
    {
        return fieldChild( parent, NodeField::Argument );   // `ops->open( x )`: a call through a function-pointer FIELD
    }
    // FE-B: the implicit-receiver languages whose member calls recorded no shape, so a bare `flush()` and `w.flush()`
    // were one reference. A receiver here makes the call a member call; its absence keeps it bare (an implicit this).
    if( lang == Lang::Java && kindIs( t, "method_invocation" ) )
    {
        return fieldChild( parent, NodeField::Object );     // null for a bare `flush()`
    }
    if( lang == Lang::CSharp && kindIs( t, "member_access_expression" ) )
    {
        return fieldChild( parent, NodeField::Expression );
    }
    if( lang == Lang::CSharp && kindIs( t, "member_binding_expression" ) )
    {
        const TSNode cond = ts_node_parent( parent );         // `w?.Bump()`: the conditional access holds the receiver
        return ( !ts_node_is_null( cond ) && kindIs( ts_node_type( cond ), "conditional_access_expression" ) && ts_node_named_child_count( cond ) > 0 )
             ? ts_node_named_child( cond, 0 ) : TSNode{};
    }
    if( ( lang == Lang::Kotlin || lang == Lang::Swift ) && kindIs( t, "navigation_suffix" ) )
    {
        const TSNode nav = ts_node_parent( parent );
        return ( !ts_node_is_null( nav ) && kindIs( ts_node_type( nav ), "navigation_expression" ) && ts_node_named_child_count( nav ) > 0 )
             ? ts_node_named_child( nav, 0 ) : TSNode{};
    }
    return TSNode{};
}

// One receiver NODE → its RecvShape. `allowChain` is the ONE-hop bound: true at the call's immediate
// receiver (a member-access receiver descends exactly one level, re-asking the same questions of its
// INNER receiver), false inside that descent — so a depth-3 chain's inner member-access classifies None
// and the whole chain degrades to the honest §2a split. `test/chainguardcheck.sh` arm (h) pins the
// bound, and the residual it leaves, as disclosed.
// Ruby's receiver node kinds that are not an (identifier), #267: `self`, and a class/module CONSTANT.
// A class/module RECEIVER is its own node kind — `Calc` is (constant), `Outer::Engine` and
// `::Top` are (scope_resolution) — never an (identifier). Without this helper every `Cls.m(…)` call
// classified None, receiverOf stamped it FieldOfVar with an empty recvVar, and resolve.h's Rule 2c
// ("the receiver token IS the type") could not fire on the one Ruby call form that carries a type.
// The type name is the FINAL constant segment (`Outer::Engine` → `Engine`, `::Top` → `Top`): the same
// final-segment convention Rule 2's type bindings use (`ns::Foo` → `Foo`), and the one that meets
// Symbol::scope, which is the IMMEDIATE enclosing name by design (ingest_sidecap.h). A
// (scope_resolution) whose `name:` child is not a (constant) is not a constant receiver and falls
// through to the honest ladder. `Outer::run( 1 )` never arrives as a scope_resolution at all —
// tree-sitter-ruby parses it as an ordinary (call) with a (constant) receiver, exactly like
// `Outer.run( 1 )`, so both spellings narrow through the (constant) arm. test/rubyrecvnarrowcheck.sh.
// The FINAL constant segment a (constant) / (scope_resolution) names — `Calc` → `Calc`, `Outer::Engine` → `Engine` —
// or empty when the node is a (scope_resolution) whose `name:` is not a (constant). Callers have checked the kind.
inline std::string_view rubyFinalConstant( TSNode node, std::string_view src )
{
    if( kindIs( ts_node_type( node ), "constant" ) )
    {
        return pattern::nodeText( node, src );
    }
    return fieldChildTextOfKind( node, NodeField::Name, "constant", src );
}

inline bool isRubyConstantNode( TSNode node ) noexcept
{
    const char* t = ts_node_type( node );
    return kindIs( t, "constant" ) || kindIs( t, "scope_resolution" );
}

// An RSpec EXAMPLE GROUP call: describe/context (and the feature/example_group and x-/f- spellings), called bare or
// on `RSpec`. 1 = a group, 2 = a SHARED group (shared_examples/_for, shared_context), 0 = neither. A shared group's
// body runs inside whichever group INCLUDES it, so its described_class is not its lexical parent's.
inline int rspecGroupKind( TSNode call, std::string_view src )
{
    const TSNode recv = fieldChild( call, NodeField::Receiver );
    if( !ts_node_is_null( recv ) && !( kindIs( ts_node_type( recv ), "constant" ) && pattern::nodeText( recv, src ) == "RSpec" ) )
    {
        return 0;
    }
    const TSNode method = fieldChild( call, NodeField::Method );
    if( ts_node_is_null( method ) )
    {
        return 0;
    }
    static constexpr std::string_view kGroups[] = { "describe", "context", "feature", "example_group",
                                                    "xdescribe", "fdescribe", "xcontext", "fcontext" };
    static constexpr std::string_view kShared[] = { "shared_examples", "shared_examples_for", "shared_context" };
    const std::string_view m = pattern::nodeText( method, src );
    if( std::ranges::find( kGroups, m ) != std::end( kGroups ) )
    {
        return 1;
    }
    return std::ranges::find( kShared, m ) != std::end( kShared ) ? 2 : 0;
}

// One example group's FIRST description argument, as RSpec reads it: nullopt when it is nil or a String (the parent
// group's described class stands), otherwise the answer — a constant's final segment, or empty for anything else
// (`describe :sym`, a variable), which names no class this tool can resolve.
inline std::optional<std::string_view> rspecGroupArgument( TSNode call, std::string_view src )
{
    const TSNode args  = fieldChild( call, NodeField::Arguments );
    const TSNode first = ts_node_is_null( args ) ? args : ts_node_named_child( args, 0 );
    if( ts_node_is_null( first ) || kindIs( ts_node_type( first ), "string" ) || kindIs( ts_node_type( first ), "nil" ) )
    {
        return std::nullopt;
    }
    return isRubyConstantNode( first ) ? rubyFinalConstant( first, src ) : std::string_view {};
}

// True when the file defines a METHOD named described_class — any `:described_class` symbol (`let( :described_class )`,
// `subject( :described_class )`, `define_method( :described_class )`) or `def described_class` / `def self.described_class`.
// A method reaches every example in its group, so the file's sites decline (floor (e)). Conservative on purpose, but a
// whole word: `:described_class_name` and `my_described_class` are other names.
inline bool rubyDefinesDescribedClassMethod( std::string_view src ) noexcept
{
    static constexpr std::string_view kName = "described_class";
    for( std::size_t at = src.find( kName ); at != std::string_view::npos; at = src.find( kName, at + kName.size() ) )
    {
        const std::size_t end = at + kName.size();
        if( end < src.size() && ( namesplit::isIdentChar( src[ end ] ) || src[ end ] == '?' || src[ end ] == '!' ) )
        {
            continue;   // `described_class_name`, `described_class?` — another name
        }
        const std::string_view before = src.substr( 0, at );
        if( before.ends_with( ':' ) || before.ends_with( "def " ) || before.ends_with( "def self." ) )
        {
            return true;
        }
    }
    return false;
}

// How a Ruby node kind takes part in LOCAL scoping — Ruby's own parse-time rule, read by rubyDescribedClassIsLocal and by
// captureRubyBareCalls. A Closure (a block, a lambda) keeps its locals in but sees the enclosing ones; a Wall (a def, a
// class, a module) sees no outer local; the Binds* kinds bind a local — the `left:` child, the `name:` child (not a
// parameter's default value), any child identifier, the `pattern:` child (`for x in`, `in x`, `v => x`), a hash
// pattern's key (`in { x: }` binds x; `in { k: x }` binds x), or the named groups of a regex literal matched with `=~`
// (`/(?<x>…)/ =~ s` — Ruby binds them only for a literal on the LEFT that holds no interpolation).
enum class RubyLocalRole : std::uint8_t { Closure, Wall, BindsLeft, BindsName, BindsChildren, BindsPattern, BindsKey, BindsRegexGroups };
struct RubyLocalKind
{
    std::string_view kind;
    RubyLocalRole    role;
};
inline constexpr RubyLocalKind kRubyLocalKinds[] = {
    { "block", RubyLocalRole::Closure },                        { "do_block", RubyLocalRole::Closure },
    { "lambda", RubyLocalRole::Closure },                       { "method", RubyLocalRole::Wall },
    { "singleton_method", RubyLocalRole::Wall },                { "class", RubyLocalRole::Wall },
    { "singleton_class", RubyLocalRole::Wall },                 { "module", RubyLocalRole::Wall },
    { "assignment", RubyLocalRole::BindsLeft },                 { "operator_assignment", RubyLocalRole::BindsLeft },
    { "optional_parameter", RubyLocalRole::BindsName },         { "keyword_parameter", RubyLocalRole::BindsName },
    { "block_parameters", RubyLocalRole::BindsChildren },       { "method_parameters", RubyLocalRole::BindsChildren },
    { "lambda_parameters", RubyLocalRole::BindsChildren },      { "left_assignment_list", RubyLocalRole::BindsChildren },
    { "destructured_left_assignment", RubyLocalRole::BindsChildren }, { "rest_assignment", RubyLocalRole::BindsChildren },
    { "destructured_parameter", RubyLocalRole::BindsChildren }, { "splat_parameter", RubyLocalRole::BindsChildren },
    { "hash_splat_parameter", RubyLocalRole::BindsChildren },   { "block_parameter", RubyLocalRole::BindsChildren },
    { "exception_variable", RubyLocalRole::BindsChildren },     { "for", RubyLocalRole::BindsPattern },
    { "in_clause", RubyLocalRole::BindsPattern },               { "match_pattern", RubyLocalRole::BindsPattern },
    { "test_pattern", RubyLocalRole::BindsPattern },            { "array_pattern", RubyLocalRole::BindsChildren },
    { "find_pattern", RubyLocalRole::BindsChildren },           { "as_pattern", RubyLocalRole::BindsName },
    { "keyword_pattern", RubyLocalRole::BindsKey },             { "binary", RubyLocalRole::BindsRegexGroups },
};

inline std::optional<RubyLocalRole> rubyLocalRole( const char* t ) noexcept
{
    const auto it = std::ranges::find( kRubyLocalKinds, std::string_view( t ), &RubyLocalKind::kind );
    return it == std::end( kRubyLocalKinds ) ? std::nullopt : std::optional<RubyLocalRole>( it->role );
}

// The one field a BindsLeft / BindsName / BindsPattern node binds through, indexed by RubyLocalRole; Count for the rest.
inline constexpr NodeField kRubyBindingField[] = { NodeField::Count, NodeField::Count, NodeField::Left, NodeField::Name,
                                                   NodeField::Count, NodeField::Pattern, NodeField::Count, NodeField::Count };
static_assert( std::size( kRubyBindingField ) == std::size_t( RubyLocalRole::BindsRegexGroups ) + 1, "one row per RubyLocalRole" );

// The `key:` of a hash pair or hash-pattern pair written with no value — `{ payload: }`, `in { x: }` — or null. Ruby
// reads that key as a name: the hash shorthand reads `payload`, the pattern binds `x`.
inline TSNode rubyShorthandKey( TSNode pair ) noexcept
{
    const TSNode key = fieldChild( pair, NodeField::Key );
    const bool   bare = ts_node_is_null( fieldChild( pair, NodeField::Value ) ) && !ts_node_is_null( key ) && kindIs( ts_node_type( key ), "hash_key_symbol" );
    return bare ? key : TSNode {};
}

// `/(?<x>…)/ =~ s` binds each named group `(?<x>…)` as a local — Ruby's rule, for a regex LITERAL on the left of `=~`
// that holds no interpolation. Each name is handed to `onName`; `(?<=` / `(?<!` are lookbehinds and name nothing.
template<class OnName>
inline void rubyRegexMatchGroups( TSNode binary, std::string_view src, OnName&& onName )
{
    const TSNode left = fieldChild( binary, NodeField::Left );
    if( ts_node_is_null( left ) || !kindIs( ts_node_type( left ), "regex" ) || nodeFieldText( binary, NodeField::Operator, src ) != "=~" )
    {
        return;
    }
    for( std::uint32_t i = 0, cc = ts_node_named_child_count( left ); i < cc; ++i )
    {
        if( kindIs( ts_node_type( ts_node_named_child( left, i ) ), "interpolation" ) )
        {
            return;
        }
    }
    const std::string_view re = pattern::nodeText( left, src );
    for( std::size_t at = re.find( "(?<" ); at != std::string_view::npos; at = re.find( "(?<", at + 3 ) )
    {
        std::size_t end = at + 3;
        while( end < re.size() && namesplit::isIdentChar( re[ end ] ) )
        {
            ++end;
        }
        if( end > at + 3 && end < re.size() && re[ end ] == '>' )
        {
            onName( re.substr( at + 3, end - at - 3 ) );
        }
    }
}

// Every local `n` (whose kind plays `role`) binds: `onNode( identifier )` for a binding spelled by an (identifier) child —
// that node is the binding site, never a read — and `onText( name )` for one spelled by no identifier node (a hash
// pattern's `key:` shorthand, a regex named group). The one reading of kRubyLocalKinds' Binds* roles.
template<class OnNode, class OnText>
inline void rubyForEachBinding( TSNode n, RubyLocalRole role, std::string_view src, OnNode&& onNode, OnText&& onText )
{
    const auto bindIdentifier = [ & ]( TSNode c )
    {
        if( !ts_node_is_null( c ) && kindIs( ts_node_type( c ), "identifier" ) )
        {
            onNode( c );
        }
    };
    if( const NodeField f = kRubyBindingField[ std::size_t( role ) ]; f != NodeField::Count )
    {
        bindIdentifier( fieldChild( n, f ) );
    }
    else if( role == RubyLocalRole::BindsChildren )
    {
        for( std::uint32_t i = 0, cc = ts_node_named_child_count( n ); i < cc; ++i )
        {
            bindIdentifier( ts_node_named_child( n, i ) );
        }
    }
    else if( role == RubyLocalRole::BindsKey )
    {
        bindIdentifier( fieldChild( n, NodeField::Value ) );   // `in { k: x }`
        if( const TSNode key = rubyShorthandKey( n ); !ts_node_is_null( key ) )
        {
            onText( pattern::nodeText( key, src ) );         // `in { x: }` — the key is the local
        }
    }
    else if( role == RubyLocalRole::BindsRegexGroups )
    {
        rubyRegexMatchGroups( n, src, onText );
    }
}

// True when `n`, whose kind plays `role`, itself BINDS the local described_class.
inline bool rubyNodeBindsDescribedClass( TSNode n, std::optional<RubyLocalRole> role, std::string_view src )
{
    if( !role )
    {
        return false;
    }
    static constexpr std::string_view kName = "described_class";
    bool binds = false;
    rubyForEachBinding( n, *role, src, [ & ]( TSNode c ) { binds = binds || pattern::nodeText( c, src ) == kName; },
                        [ & ]( std::string_view name ) { binds = binds || name == kName; } );
    return binds;
}

// True when a child of `n` that ENDS before byte `at` — an earlier statement, a block's or a def's parameters — binds
// described_class, searched without entering a nested block, lambda, def, class or module, whose locals never reach
// past it. `stack` is the caller's scratch, so a hostile nesting depth costs heap, not stack.
inline bool rubyEarlierChildBindsDescribedClass( TSNode n, std::uint32_t at, std::string_view src, std::vector<TSNode>& stack )
{
    stack.clear();
    const std::uint32_t cc = ts_node_named_child_count( n );
    for( std::uint32_t i = 0; i < cc && ts_node_end_byte( ts_node_named_child( n, i ) ) <= at; ++i )
    {
        stack.push_back( ts_node_named_child( n, i ) );
    }
    while( !stack.empty() )
    {
        const TSNode cur = stack.back();
        stack.pop_back();
        const std::optional<RubyLocalRole> role = rubyLocalRole( ts_node_type( cur ) );
        if( rubyNodeBindsDescribedClass( cur, role, src ) )
        {
            return true;
        }
        if( role == RubyLocalRole::Closure || role == RubyLocalRole::Wall )
        {
            continue;   // a nested scope's locals never reach the site
        }
        const std::uint32_t kids = ts_node_named_child_count( cur );
        for( std::uint32_t i = 0; i < kids; ++i )
        {
            stack.push_back( ts_node_named_child( cur, i ) );
        }
    }
    return false;
}

// True when the (identifier) `site` reads a LOCAL named described_class, not RSpec's method — Ruby's own rule: a local
// is visible after its binding, in its own scope and in the blocks nested inside it. So the walk climbs from the site,
// searching each enclosing node's earlier children, and stops after the first def, class or module. An enclosing
// assignment counts too: in `described_class = described_class.m` the right side already reads the local. Floor (e).
inline bool rubyDescribedClassIsLocal( TSNode site, std::string_view src )
{
    const std::uint32_t at = ts_node_start_byte( site );
    std::vector<TSNode> stack;
    for( TSNode n = ts_node_parent( site ); !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        const std::optional<RubyLocalRole> role = rubyLocalRole( ts_node_type( n ) );
        if( rubyNodeBindsDescribedClass( n, role, src ) || rubyEarlierChildBindsDescribedClass( n, at, src, stack ) )
        {
            return true;
        }
        if( role == RubyLocalRole::Wall )
        {
            break;   // a def, class or module: no outer local reaches in
        }
    }
    return false;
}

// RSpec's `described_class` — a bare (identifier) receiver no binding names — read as the constant it IS. RSpec's
// own rule (rspec-core 3.13, Metadata::ExampleGroupHash#described_class): a group's described class is its FIRST
// description argument unless that is nil or a String; otherwise it is the parent group's. So the walk climbs the
// enclosing calls whose BLOCK holds the site (the child it came from is a do_block/block), and the innermost example
// group with a constant first argument answers. A string or absent argument passes outward; any other argument
// (`describe :sym`, a variable) and a shared group stop the walk with no answer, and the site is left exactly as it
// was. test/rubydescribedclasscheck.sh. rspecDescribingGroup is the climb: the group that answers, or a null node.
inline TSNode rspecDescribingGroup( TSNode node, std::string_view src )
{
    TSNode prev = node;
    for( TSNode n = ts_node_parent( node ); !ts_node_is_null( n ); prev = n, n = ts_node_parent( n ) )
    {
        const char* pt = ts_node_type( prev );
        if( !kindIs( ts_node_type( n ), "call" ) || !( kindIs( pt, "do_block" ) || kindIs( pt, "block" ) ) )
        {
            continue;   // not a call, or the site is in its receiver/arguments rather than its block
        }
        const int group = rspecGroupKind( n, src );
        if( group == 2 )
        {
            return TSNode {};  // a shared group: its body runs in whichever group includes it
        }
        if( group == 1 && rspecGroupArgument( n, src ) )
        {
            return n;
        }
    }
    return TSNode {};
}

inline std::string_view rspecDescribedClass( TSNode node, std::string_view src )
{
    const TSNode group = rspecDescribingGroup( node, src );
    return ts_node_is_null( group ) ? std::string_view {} : rspecGroupArgument( group, src ).value_or( std::string_view {} );
}

// The described class AS WRITTEN (parser version 137): the describing group's constant argument whole
// (`BankIntegration::Sync`, where rspecDescribedClass answers its final segment); empty when that answers none.
inline std::string_view rspecDescribedPath( TSNode node, std::string_view src )
{
    const TSNode group = rspecDescribingGroup( node, src );
    const TSNode args  = ts_node_is_null( group ) ? group : fieldChild( group, NodeField::Arguments );
    const TSNode first = ts_node_is_null( args ) ? args : ts_node_named_child( args, 0 );
    return !ts_node_is_null( first ) && rubyIsConstantChain( first ) ? pattern::nodeText( first, src ) : std::string_view {};
}

// ─── Ruby's BARE-WORD call (test/rubybarecallcheck.sh) ────────────────────────────────────────────────────────────────
// `full_name`, `render_profile`, the `items` of `items.sum`: an identifier with no receiver, no arguments and no
// parentheses parses as a plain (identifier) — the node a local read is — so queries/ruby/tags.scm cannot capture it,
// and one Ruby call site in five minted no reference at all. Ruby's parser tells the two apart LEXICALLY, and
// captureRubyBareCalls applies that rule: an identifier is a local exactly when a binding of its name (kRubyLocalKinds'
// Binds* roles) precedes it in its own scope or in an enclosing Closure's, up to the nearest Wall; every other bare
// identifier is a method call on self (Prism: CallNode#variable_call?). It becomes a receiver-less call reference, the
// shape resolve.h's Rule 1 and its base walk already read as an implicit-self send.
//
// The bindings land when the walk reaches the BINDING node, before its children, so `x = x` reads the local on its
// right (Ruby's own reading) and a parameter's default value sees the parameters bound before it. A hash or keyword-
// argument shorthand (`{ payload: }`) reads `payload` and is a call when no local has that name. Inside a block or
// lambda with no parameter list, `it` and `_1`…`_9` are its implicit parameters (Ruby 3.4).
//
// RSpec: the let family DEFINES a method on its example group, visible to the whole group — before the line that
// defines it, in nested groups, and through a `def` inside the group (a method calling a method) — and every example
// group defines `subject`. Those names bind like locals over the group's block, stopped only by a class/module wall, so a
// spec's `user` never reaches an application `def user`. They are not minted as definitions: a let is reachable only
// from its group, and a definition application code could name would turn unique application calls into declines.
//
// Floors, pinned by the gate: `defined?( x )` calls nothing and is not walked; a shared context's lets are unknown in
// the including file; run-time locals (`binding.local_variable_set`, `eval`) are invisible; and inside
// `instance_eval`/`class_eval` blocks the call still resolves against the lexical class, as a parenthesised `m()` does.
inline constexpr std::string_view kRubyLetFamily[] = { "let", "let!", "subject", "subject!", "let_it_be", "let_it_be_with_reload", "let_it_be_with_refind" };

// The local names visible at the walk's position: one frame per open Ruby scope, each name a stack of the frames that
// bind it (deepest last), so a lookup is one hash probe whatever the scope's width.
struct RubyLocalScopes
{
    struct Frame
    {
        std::uint32_t endByte;          // the scope node's end: the frame closes at the first node starting at or past it
        std::uint32_t wall;             // index of the innermost Wall frame — this one, when it is a Wall
        std::uint32_t classWall;        // index of the innermost class/module/`class <<`/file frame: where a let stops
        std::uint32_t firstBound;       // this frame's names in `bound` start here
        bool          implicitParams;   // a block or lambda with no parameter list
    };
    struct Entry { std::uint32_t depth; bool let; };   // one frame binding a name: a local, or a let
    std::vector<Frame>                                 frames;
    std::vector<std::string_view>                      bound;
    HashMap<std::string_view, rw::SmallVec<Entry, 2>>  names;

    void push( std::uint32_t endByte, bool wall, bool classLike, bool implicitParams )
    {
        const std::uint32_t depth = std::uint32_t( frames.size() );
        const Frame         outer = frames.empty() ? Frame {} : frames.back();
        frames.push_back( Frame { endByte, wall ? depth : outer.wall, classLike ? depth : outer.classWall, std::uint32_t( bound.size() ), implicitParams } );
    }

    // close every frame whose node ended at or before `atByte` — never the file's own
    void closeEndedBy( std::uint32_t atByte )
    {
        while( frames.size() > 1 && frames.back().endByte <= atByte )
        {
            for( std::size_t i = frames.back().firstBound; i < bound.size(); ++i )
            {
                names.find( bound[ i ] )->second.pop_back();   // a name's deepest entry is the innermost frame's
            }
            bound.resize( frames.back().firstBound );
            frames.pop_back();
        }
    }

    void bind( std::string_view name, bool let )
    {
        const std::uint32_t     depth   = std::uint32_t( frames.size() - 1 );
        rw::SmallVec<Entry, 2>& entries = names[ name ];
        if( entries.empty() || entries.back().depth != depth || entries.back().let != let )
        {
            entries.push_back( Entry { depth, let } );
            bound.push_back( name );
        }
    }

    // a local up to the innermost wall, a let up to the innermost class wall, or a block's implicit parameter
    bool visible( std::string_view name ) const
    {
        const Frame& top = frames.back();
        if( const auto it = names.find( name ); it != names.end() )
        {
            for( auto e = it->second.rbegin(); e != it->second.rend() && e->depth >= top.classWall; ++e )
            {
                if( e->let || e->depth >= top.wall )
                {
                    return true;
                }
            }
        }
        const bool implicitName = name == "it" || ( name.size() == 2 && name[ 0 ] == '_' && name[ 1 ] >= '1' && name[ 1 ] <= '9' );   // `it`, `_1`…`_9`
        return implicitName && std::any_of( frames.begin() + top.wall, frames.end(), []( const Frame& f ) { return f.implicitParams; } );
    }
};

// The first argument of a call when it is a plain symbol — `:user` → user — or empty.
inline std::string_view rubyFirstSymbolArgument( TSNode call, std::string_view src )
{
    const TSNode args  = fieldChild( call, NodeField::Arguments );
    const TSNode first = ts_node_is_null( args ) ? args : ts_node_named_child( args, 0 );
    if( ts_node_is_null( first ) || !kindIs( ts_node_type( first ), "simple_symbol" ) )
    {
        return {};
    }
    const std::string_view sym = pattern::nodeText( first, src );
    return sym.substr( sym.empty() ? 0 : 1 );
}

// The name one statement of an example group's body defines, or empty: a receiver-less let-family call, named by its
// first simple_symbol argument — a nameless `subject { … }` defines `subject`.
inline std::string_view rubyLetFamilyName( TSNode c, std::string_view src )
{
    if( !kindIs( ts_node_type( c ), "call" ) || !ts_node_is_null( fieldChild( c, NodeField::Receiver ) ) )
    {
        return {};
    }
    const std::string_view m = fieldChildTextOfKind( c, NodeField::Method, "identifier", src );
    if( std::ranges::find( kRubyLetFamily, m ) == std::end( kRubyLetFamily ) )
    {
        return {};
    }
    const std::string_view name = rubyFirstSymbolArgument( c, src );
    return name.empty() && m.starts_with( "subject" ) ? std::string_view( "subject" ) : name;
}

// The block a Ruby call is given — its last named child (tree-sitter-ruby's `block:` field) — or null.
inline TSNode rubyCallBlock( TSNode call )
{
    const std::uint32_t cc = ts_node_named_child_count( call );
    const TSNode        last = cc == 0 ? TSNode {} : ts_node_named_child( call, cc - 1 );
    return !ts_node_is_null( last ) && ( kindIs( ts_node_type( last ), "do_block" ) || kindIs( ts_node_type( last ), "block" ) ) ? last : TSNode {};
}

// The block of an RSpec example-group call, or null.
inline TSNode rspecGroupBlock( TSNode call, std::string_view src )
{
    return rspecGroupKind( call, src ) == 0 ? TSNode {} : rubyCallBlock( call );
}

// Is `c` a child of `n` that NAMES something — a method, an alias — rather than reading a value? `call`'s `method:` is
// the tags query's capture already; a def's `name:` and `object:`, a setter's name and alias/undef operands read nothing.
inline bool rubyNamingChild( TSNode n, const char* t, TSNode c ) noexcept
{
    if( kindIs( t, "call" ) )
    {
        return ts_node_eq( c, fieldChild( n, NodeField::Method ) );
    }
    if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
    {
        return ts_node_eq( c, fieldChild( n, NodeField::Name ) ) || ts_node_eq( c, fieldChild( n, NodeField::Object ) );
    }
    return kindIs( t, "setter" ) || kindIs( t, "alias" ) || kindIs( t, "undef" );
}

// FE-B on #373: a Ruby receiver the code builds, typed in the reference's own fields (model.h rubyTypedRecvOf)
inline void rubyTypeReceiver( RawRef& ref, std::string_view type, std::string_view via, bool factory )
{
    ref.recvVar.clear();
    ref.memberCtor.assign( type );
    ref.memberVia.assign( via );
    ref.memberFactory = factory;
}

// ─── Ruby's TYPED receiver (test/rubytypedrecvcheck.sh, parser version 132) ───────────────────────────────────────────
// A receiver the code BUILDS is an instance of one class, and Ruby's method lookup on that class decides which `def` a call
// on it reaches (graph.h rubyTypedReceiver). What builds one is read from what the expression IS: `Const.new( … )` and the
// Active Record finders on a constant (kRubyTypedFinders — `User.find_by( … )` returns a User), `described_class.new`
// inside an example group that describes a constant, and a FactoryBot build — `create`/`build`/`build_stubbed( :user, … )`,
// receiver-less inside an example group or on `FactoryBot` anywhere — whose class only the tree's factory definitions
// know (captureRubyFactories). A call's receiver is typed when it is one of those written in place, a local whose every
// binding in its scope builds the same one, or the let/subject RSpec runs for that name there — the innermost definition,
// a nested group's override included — where a group with no subject of its own has its parent's, and at the top
// `described_class.new`. RubyBareCallWalk reads all of it on the walk it already makes, beside the locals it tracks, and
// typeReceivers writes each type into its call reference (rubyTypeReceiver above; model.h rubyTypedRecvOf). Floors (test/rubytypedrecvcheck.sh):
// control flow is not read (one binding of another shape anywhere in the scope, a parameter or a block parameter
// included, leaves the local untyped); instance variables, return values and a shared context's lets are not typed.
// RSpec's own builders are read the same way (test/rubyrspectargetcheck.sh, parser version 133): inside an example
// group a receiver-less `expect( v )`, `allow( v )`, `expect_any_instance_of( K )`, `allow_any_instance_of( K )` and a
// bare `is_expected` build one of RSpec's target classes (model.h kRspecTargets; `expect { … }` a BlockExpectationTarget),
// so `expect( v ).to` is a call on RSpec's object. Not read: outside a group (a helper module a `config.include` mixes
// in). A matcher builder (`receive`, `change`, …) is one of them too, and a call on a chain rooted at one — the `to` of
// `change { }.from( a ).to( b )`, `.and_return` after `receive( :m ).with( 1 )` — is typed as the root, through at most
// kRubyMatcherChainLinks links (rubyMatcherChainType, parser version 136).
inline constexpr std::string_view kRubyTypedFinders[] = { "create", "create!", "find", "find_by", "find_by!", "find_or_create_by", "find_or_create_by!",
                                                          "find_or_initialize_by", "find_sole_by", "first", "first!", "last", "last!", "new", "sole",
                                                          "take", "take!" };
inline constexpr std::string_view kRubyFactoryBuilds[] = { "build", "build_stubbed", "create" };
inline constexpr std::size_t      kRubyMatcherChainLinks = 8;   // a chain is short; a hostile one costs a bounded walk

// What one value builds: a class's constant as written, or a factory name (`factory`), and the method that built it. Empty
// `type` = untyped. Views into the file's source.
struct RubyValueType
{
    std::string_view type;
    std::string_view via;
    bool             factory = false;
    bool operator==( const RubyValueType& ) const = default;
};

// Where a value is read: inside an example group's block (a receiver-less `create( :user )` is FactoryBot's there), and
// the class `described_class` names at the site — empty when no constant-described group encloses it or the file
// redefines the name. The walk keeps both per frame, so neither costs a climb up the tree.
struct RubyValueSite
{
    bool             inGroup = false;
    std::string_view described;
};

// What a FactoryBot build `v` to `m` builds — its factory, named by its first symbol argument — when `m` is a build
// (kRubyFactoryBuilds).
inline RubyValueType rubyFactoryBuildType( TSNode v, std::string_view m, std::string_view src )
{
    const bool             build   = std::ranges::find( kRubyFactoryBuilds, m ) != std::end( kRubyFactoryBuilds );
    const std::string_view factory = build ? rubyFirstSymbolArgument( v, src ) : std::string_view {};
    return factory.empty() ? RubyValueType {} : RubyValueType { factory, m, true };
}

// What a receiver-less call `v` to `m` builds inside an example group: one of RSpec's targets (model.h kRspecTargets —
// `expect { … }`, a block and no argument, is the block form), else a FactoryBot build (`create( :user )`). A bare word
// (`is_expected`) is such a call with no arguments.
inline RubyValueType rubyGroupBuildType( TSNode v, std::string_view m, std::string_view src )
{
    const auto target = std::ranges::find( kRspecTargets, m, &RspecTarget::builder );
    if( target == std::end( kRspecTargets ) )
    {
        return rubyFactoryBuildType( v, m, src );
    }
    const bool block = kindIs( ts_node_type( v ), "call" ) && ts_node_is_null( fieldChild( v, NodeField::Arguments ) ) && !ts_node_is_null( rubyCallBlock( v ) );
    return RubyValueType { m == "expect" && block ? kRspecBlockTarget : target->cls, m, false };
}

// What a matcher chain `v` inside an example group builds: the class of the RSpec builder at its root — the receiver-less
// call fewer than kRubyMatcherChainLinks receivers below `v`, so a call on `v` is at most that many links from it — whose
// every link is RSpec's; untyped for any other root (a FactoryBot build's methods return anything).
inline RubyValueType rubyMatcherChainType( TSNode v, std::string_view src )
{
    TSNode link = v;
    for( std::size_t depth = 0; depth < kRubyMatcherChainLinks && !ts_node_is_null( link ) && kindIs( ts_node_type( link ), "call" ); ++depth )
    {
        const TSNode recv = fieldChild( link, NodeField::Receiver );
        if( ts_node_is_null( recv ) )
        {
            const RubyValueType root = rubyGroupBuildType( link, fieldChildTextOfKind( link, NodeField::Method, "identifier", src ), src );
            return root.factory ? RubyValueType {} : root;
        }
        link = recv;
    }
    return {};
}

// What a call `v` to `m` on `recv` builds, read at `site`: a FactoryBot build on `FactoryBot`, a finder on any other
// constant — the constant AS WRITTEN (`OpenSSL::Cipher`): graph.h reads a qualified one only when the tree opens that
// path — `described_class.new`, or a link of a matcher chain in an example group.
inline RubyValueType rubyReceiverBuildType( TSNode v, TSNode recv, std::string_view m, std::string_view src, const RubyValueSite& site )
{
    const std::string_view on = isRubyConstantNode( recv ) ? rubyFinalConstant( recv, src ) : std::string_view {};
    if( ( on == "FactoryBot" || on == "FactoryGirl" ) && std::ranges::find( kRubyFactoryBuilds, m ) != std::end( kRubyFactoryBuilds ) )
    {
        return rubyFactoryBuildType( v, m, src );
    }
    if( !on.empty() )
    {
        const bool finder = std::ranges::find( kRubyTypedFinders, m ) != std::end( kRubyTypedFinders );
        return finder ? RubyValueType { pattern::nodeText( recv, src ), m, false } : RubyValueType {};
    }
    const bool describedNew = m == "new" && kindIs( ts_node_type( recv ), "identifier" ) && pattern::nodeText( recv, src ) == "described_class";
    if( describedNew )
    {
        return site.described.empty() ? RubyValueType {} : RubyValueType { site.described, m, false };
    }
    return site.inGroup ? rubyMatcherChainType( v, src ) : RubyValueType {};
}

// What the value expression `v` builds (the section note above), read at `site`.
inline RubyValueType rubyValueType( TSNode v, std::string_view src, const RubyValueSite& site )
{
    const bool word = !ts_node_is_null( v ) && kindIs( ts_node_type( v ), "identifier" );   // a bare `is_expected`
    if( !word && ( ts_node_is_null( v ) || !kindIs( ts_node_type( v ), "call" ) ) )
    {
        return {};
    }
    const std::string_view m    = word ? pattern::nodeText( v, src ) : fieldChildTextOfKind( v, NodeField::Method, "identifier", src );
    const TSNode           recv = word ? TSNode {} : fieldChild( v, NodeField::Receiver );
    if( ts_node_is_null( recv ) )
    {
        return site.inGroup ? rubyGroupBuildType( v, m, src ) : RubyValueType {};
    }
    return rubyReceiverBuildType( v, recv, m, src, site );
}

// What a let/subject call's block returns — its body's last statement — or null.
inline TSNode rubyLetValue( TSNode letCall )
{
    const TSNode block = rubyCallBlock( letCall );
    const TSNode body  = ts_node_is_null( block ) ? block : fieldChild( block, NodeField::Body );
    TSNode       last {};
    if( !ts_node_is_null( body ) )
    {
        ChildCursor cursor( body );   // O(children): a body is as wide as its comments (src/infra/tschildren.h)
        forEachNamedChild( body, cursor.cur, [ & ]( TSNode c ) { last = kindIs( ts_node_type( c ), "comment" ) ? last : c; return true; } );
    }
    return last;
}

// ─── Ruby's DECLARED calls (test/rubydeclrefcheck.sh, parser version 134) ─────────────────────────────────────────────
// A Rails declaration names, by SYMBOL, a method the framework calls later on the class's instances: `before_action
// :authenticate`, `after_save :reindex`, `validate :name_present`, an `if:` / `unless:` condition, `rescue_from …, with:
// :not_found`. Nothing in the source calls the method, so each symbol is read as a call to it — a receiver-less call from
// the class body, whose self's lookup is the class's (graph.h RubySelfReach) — when the macro sits at class-body position
// (receiver-less, the innermost def-or-class wall a class or module body: a concern's `included do` block counts, a def
// does not). `send`/`public_send`/`__send__`/`try`/`try!`/`method` with a literal symbol call that method on the same
// receiver: the call's own reference, renamed (RubyBareCallWalk::sendTargets). Floors (test/rubydeclrefcheck.sh): option
// values that are not calls (`only:`, `except:`, `on:`), `validates`' attribute names, `skip_*_action`, `set_callback`, a
// string or computed name, and a callback macro inside a def make none.
inline constexpr std::string_view kRubyCallbackMacros[] = {
    // ActionController, ActionMailer, AbstractController
    "before_action", "after_action", "around_action", "prepend_before_action", "prepend_after_action", "prepend_around_action",
    "append_before_action", "append_after_action", "append_around_action", "before_filter", "after_filter", "around_filter",
    // ActiveModel, ActiveRecord
    "before_validation", "after_validation", "before_save", "around_save", "after_save", "before_create", "around_create",
    "after_create", "before_update", "around_update", "after_update", "before_destroy", "around_destroy", "after_destroy",
    "after_commit", "after_rollback", "after_create_commit", "after_update_commit", "after_destroy_commit", "after_save_commit",
    "after_initialize", "after_find", "after_touch", "validate",
    // ActiveJob, ActionMailer delivery, ActionCable channels
    "before_enqueue", "around_enqueue", "after_enqueue", "before_perform", "around_perform", "after_perform", "after_discard",
    "before_deliver", "around_deliver", "after_deliver", "before_subscribe", "after_subscribe", "before_unsubscribe",
    "after_unsubscribe" };
inline constexpr std::string_view kRubySendCalls[] = { "__send__", "method", "public_send", "send", "try", "try!" };

// What a declaration's symbols name: a callback's positional symbols and its conditions, only the conditions (a
// validation's positional symbols are attributes), or rescue_from's `with:` handler.
enum class RubyDeclared : std::uint8_t { None, Callback, Conditions, Rescue };

inline RubyDeclared rubyDeclaredKind( std::string_view m ) noexcept
{
    if( std::ranges::find( kRubyCallbackMacros, m ) != std::end( kRubyCallbackMacros ) )
    {
        return RubyDeclared::Callback;
    }
    if( m == "validates" || m == "validates_with" || ( m.starts_with( "validates_" ) && m.ends_with( "_of" ) ) )
    {
        return RubyDeclared::Conditions;
    }
    return m == "rescue_from" ? RubyDeclared::Rescue : RubyDeclared::None;
}

// Is the option key `key` (`if:` or the older `:if =>`) one whose value a `kind` declaration calls?
inline bool rubyDeclaredOption( TSNode key, RubyDeclared kind, std::string_view src ) noexcept
{
    std::string_view k = ts_node_is_null( key ) ? std::string_view {} : pattern::nodeText( key, src );
    k                  = k.substr( k.starts_with( ':' ) ? 1 : 0 );
    k                  = k.substr( 0, k.size() - ( k.ends_with( ':' ) ? 1 : 0 ) );
    return k == "if" || k == "unless" || ( kind == RubyDeclared::Rescue && k == "with" );
}

// Each method symbol a `kind` declaration's arguments name, in source order (the section note above), handed to `fn`.
template<class Fn>
inline void rubyForEachDeclaredSymbol( TSNode call, RubyDeclared kind, std::string_view src, Fn&& fn )
{
    const TSNode args = fieldChild( call, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        return;
    }
    const auto symbol = []( TSNode n ) { return kindIs( ts_node_type( n ), "simple_symbol" ); };
    ChildCursor cursor( args );   // O(children) (src/infra/tschildren.h)
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        const TSNode value = kindIs( ts_node_type( a ), "pair" ) && rubyDeclaredOption( fieldChild( a, NodeField::Key ), kind, src )
                                 ? fieldChild( a, NodeField::Value ) : TSNode {};
        if( kind == RubyDeclared::Callback && symbol( a ) )
        {
            fn( a );
        }
        else if( !ts_node_is_null( value ) && symbol( value ) )
        {
            fn( value );
        }
        else if( !ts_node_is_null( value ) && kindIs( ts_node_type( value ), "array" ) )
        {
            ChildCursor inner( value );
            forEachNamedChild( value, inner.cur, [ & ]( TSNode e ) { if( symbol( e ) ) { fn( e ); } return true; } );
        }
        return true;
    } );
}

// One call whose receiver is typed (RubyBareCallWalk): the call node's start (its reference's startByte) and method,
// whether the receiver is an (identifier) — the reference's NamedVar — or a value, and what it builds; for a local, the
// scope and name whose binding types are read once the walk has seen every binding (`local` non-empty, `type` filled by
// typeReceivers).
struct RubyTypedSite
{
    std::uint32_t    callStart;
    std::string_view method;
    bool             identReceiver;
    RubyValueType    type;
    std::uint32_t    wall;
    std::string_view local;
};

// One `send`-family call naming its method by a literal symbol (RubyBareCallWalk::sendTargets): the call node's start
// and method, and the symbol.
struct RubySendSite
{
    std::uint32_t    callStart;
    std::string_view method;
    TSNode           symbol;
    std::size_t      ref  = 0;   // the call's reference, when exactly one matched (`hits` == 1)
    std::uint32_t    hits = 0;
};

// One file's bare-word calls (see the section note above): one iterative pre-order walk in source order — an explicit
// stack, no recursion, so a hostile nesting depth costs heap, not stack.
class RubyBareCallWalk
{
public:
    RubyBareCallWalk( std::uint32_t fileId, std::string_view src, std::vector<RawRef>& refs ) : fileId_( fileId ), src_( src ), refs_( refs )
    {
        scopes_.names.reserve( 64 );
        stack_.reserve( 64 );
        kids_.reserve( 16 );
    }
    void run( TSNode root );
    void typeReceivers( std::size_t firstRef, std::size_t endRef );   // after run: write each typed receiver into its call reference
    void sendTargets( std::size_t firstRef, std::size_t endRef );     // after typeReceivers: each `send( :m )`'s call to m

private:
    struct Item
    {
        TSNode node;
        bool   naming;       // an identifier in a naming or binding position: it reads nothing
        bool   groupBlock;   // the block of an RSpec example-group call
    };
    void visit( const Item& item, ChildCursor& cursor );
    void enter( TSNode n, const char* t, RubyLocalRole role, bool groupBlock );
    void bindGroupLets( TSNode block, bool groupBlock );
    void pushChildren( TSNode n, const char* t, ChildCursor& cursor );
    void emit( TSNode at, std::string_view name );
    void noteFrame( bool groupBlock, TSNode block );
    RubyValueSite valueSite() const;
    void noteLocalTypes( TSNode n, RubyLocalRole role );
    void noteLetType( TSNode letCall, std::string_view name );
    void noteImplicitSubject();
    void noteTypedCall( TSNode call );
    void noteDeclaredCall( TSNode call );
    void noteNamedReceiver( std::uint32_t at, std::string_view method, std::string_view name );
    const RubyTypedSite* siteOf( const RawRef& r ) const;
    const std::string& typeKey( std::uint32_t frame, std::string_view name );

    std::uint32_t        fileId_;
    std::string_view     src_;
    std::vector<RawRef>& refs_;
    RubyLocalScopes      scopes_;
    std::vector<Item>    stack_;
    std::vector<TSNode>  kids_;
    std::vector<TSNode>  binding_;   // the visited node's binding identifiers: its children marked `naming`
    std::vector<RubySendSite> sendSites_;

    // typed receivers (the section note above): per open frame depth, a serial naming that frame and whether it is inside
    // an example group; "<frame serial>#<name>" → what a let defines in that group / what every binding of a local in that
    // scope builds (a tombstone once two disagree); the group frames whose own subject is explicit; the typed call sites
    std::vector<std::uint32_t>              frameSerial_;
    std::vector<char>                       frameInGroup_;
    std::vector<std::string_view>           frameDescribed_;   // the class described_class names in the frame (rspecDescribedClass's rule)
    bool                                    describedRedefined_ = false;   // the file defines a method named described_class
    std::uint32_t                           nextSerial_ = 0;
    HashMap<std::string, RubyValueType>     letTypes_;
    HashMap<std::string, RubyValueType>     localTypes_;
    HashMap<std::uint32_t, RubyValueType>   explicitSubjects_;
    std::vector<RubyTypedSite>              typedSites_;
    std::string                             key_;
};

inline void RubyBareCallWalk::run( TSNode root )
{
    ChildCursor cursor( root );
    scopes_.push( ts_node_end_byte( root ), true, true, false );
    describedRedefined_ = rubyDefinesDescribedClassMethod( src_ );
    noteFrame( false, root );
    stack_.push_back( Item { root, false, false } );
    while( !stack_.empty() )
    {
        const Item item = stack_.back();
        stack_.pop_back();
        visit( item, cursor );
    }
}

inline void RubyBareCallWalk::visit( const Item& item, ChildCursor& cursor )
{
    const TSNode n = item.node;
    const char*  t = ts_node_type( n );
    scopes_.closeEndedBy( ts_node_start_byte( n ) );
    if( kindIs( t, "identifier" ) )
    {
        if( !item.naming )
        {
            emit( n, pattern::nodeText( n, src_ ) );
        }
        return;
    }
    if( kindIs( t, "unary" ) && pattern::nodeText( n, src_ ).starts_with( "defined?" ) )
    {
        return;   // floor (a): defined?( x ) asks, and calls nothing
    }
    if( const TSNode key = kindIs( t, "pair" ) ? rubyShorthandKey( n ) : TSNode {}; !ts_node_is_null( key ) )
    {
        emit( key, pattern::nodeText( key, src_ ) );   // `{ payload: }` reads payload
    }
    if( kindIs( t, "call" ) )
    {
        noteTypedCall( n );
        noteDeclaredCall( n );
    }
    binding_.clear();
    if( const std::optional<RubyLocalRole> role = rubyLocalRole( t ) )
    {
        enter( n, t, *role, item.groupBlock );
    }
    pushChildren( n, t, cursor );
}

// a scope node opens its frame (and an example group's block binds its lets); a binding node binds its names
inline void RubyBareCallWalk::enter( TSNode n, const char* t, RubyLocalRole role, bool groupBlock )
{
    if( role == RubyLocalRole::Wall || role == RubyLocalRole::Closure )
    {
        const bool closure = role == RubyLocalRole::Closure;
        scopes_.push( ts_node_end_byte( n ), !closure, kindIs( t, "class" ) || kindIs( t, "module" ) || kindIs( t, "singleton_class" ),
                      closure && ts_node_is_null( fieldChild( n, NodeField::Parameters ) ) );
        noteFrame( groupBlock, n );
        if( closure && !kindIs( t, "lambda" ) )
        {
            bindGroupLets( n, groupBlock );
        }
        return;
    }
    rubyForEachBinding( n, role, src_, [ & ]( TSNode c ) { binding_.push_back( c ); scopes_.bind( pattern::nodeText( c, src_ ), false ); },
                        [ & ]( std::string_view name ) { scopes_.bind( name, false ); } );
    noteLocalTypes( n, role );
}

// every let the block's statements define, and `subject` when the block is an example group's
inline void RubyBareCallWalk::bindGroupLets( TSNode block, bool groupBlock )
{
    if( groupBlock )
    {
        scopes_.bind( "subject", true );
        noteImplicitSubject();
    }
    const TSNode body = fieldChild( block, NodeField::Body );
    for( std::uint32_t i = 0, cc = ts_node_is_null( body ) ? 0 : ts_node_named_child_count( body ); i < cc; ++i )
    {
        if( const std::string_view name = rubyLetFamilyName( ts_node_named_child( body, i ), src_ ); !name.empty() )
        {
            scopes_.bind( name, true );
            noteLetType( ts_node_named_child( body, i ), name );
        }
    }
}

inline void RubyBareCallWalk::pushChildren( TSNode n, const char* t, ChildCursor& cursor )
{
    const TSNode groupBlock = kindIs( t, "call" ) ? rspecGroupBlock( n, src_ ) : TSNode {};
    collectChildren( n, cursor.cur, kids_ );
    for( std::size_t i = kids_.size(); i > 0; --i )
    {
        const TSNode c      = kids_[ i - 1 ];
        const bool   naming = rubyNamingChild( n, t, c ) || std::ranges::any_of( binding_, [ & ]( TSNode b ) { return ts_node_eq( b, c ); } );
        stack_.push_back( Item { c, naming, !ts_node_is_null( groupBlock ) && ts_node_eq( c, groupBlock ) } );
    }
}

// receiver-less: RecvKind::None, the implicit-self shape Rule 1 reads
inline void RubyBareCallWalk::emit( TSNode at, std::string_view name )
{
    if( !name.empty() && !scopes_.visible( name ) )
    {
        refs_.push_back( rawRefAt( at, fileId_, Lang::Ruby, RefRole::Call, std::string( name ) ) );
    }
}

// a new frame at the top of scopes_: its serial, whether it sits in an example group, and the class described_class names
// in it — rspecDescribedClass's rule, kept per frame: an example group's block takes its group's constant argument, a
// String or absent one passes the parent's through, any other argument and a shared group name none; any other frame
// inherits its parent's
inline void RubyBareCallWalk::noteFrame( bool groupBlock, TSNode block )
{
    const std::size_t depth = scopes_.frames.size() - 1;
    if( frameSerial_.size() <= depth )
    {
        frameSerial_.resize( depth + 1 );
        frameInGroup_.resize( depth + 1 );
        frameDescribed_.resize( depth + 1 );
    }
    const std::string_view parent = depth > 0 ? frameDescribed_[ depth - 1 ] : std::string_view {};
    const TSNode           group  = groupBlock ? ts_node_parent( block ) : TSNode {};
    const int              kind   = ts_node_is_null( group ) ? 0 : rspecGroupKind( group, src_ );
    const std::optional<std::string_view> argument = kind == 1 ? rspecGroupArgument( group, src_ ) : std::nullopt;
    frameSerial_[ depth ]    = nextSerial_++;
    frameInGroup_[ depth ]   = char( groupBlock || ( depth > 0 && frameInGroup_[ depth - 1 ] != 0 ) );
    frameDescribed_[ depth ] = kind == 2 ? std::string_view {} : argument ? *argument : parent;
}

// the value site at the walk's position: its group, and what described_class names there unless the file or a visible
// local or let redefines it
inline RubyValueSite RubyBareCallWalk::valueSite() const
{
    const std::size_t top       = scopes_.frames.size() - 1;
    const bool        redefined = describedRedefined_ || scopes_.visible( "described_class" );
    return RubyValueSite { frameInGroup_[ top ] != 0, redefined ? std::string_view {} : frameDescribed_[ top ] };
}

inline const std::string& RubyBareCallWalk::typeKey( std::uint32_t frame, std::string_view name )
{
    key_.clear();
    key_.append( std::to_string( frame ) ).push_back( '#' );
    key_.append( name );
    return key_;
}

// each local `n` binds, folded into its scope's type: what an assignment (or `||=`) builds; nothing, for every other binding
inline void RubyBareCallWalk::noteLocalTypes( TSNode n, RubyLocalRole role )
{
    const std::uint32_t wall    = frameSerial_[ scopes_.frames.back().wall ];
    const TSNode        left    = role == RubyLocalRole::BindsLeft ? fieldChild( n, NodeField::Left ) : TSNode {};
    const bool          assigns = !ts_node_is_null( left ) && kindIs( ts_node_type( left ), "identifier" )
                               && ( kindIs( ts_node_type( n ), "assignment" ) || nodeFieldText( n, NodeField::Operator, src_ ) == "||=" );
    const RubyValueType built   = assigns ? rubyValueType( fieldChild( n, NodeField::Right ), src_, valueSite() ) : RubyValueType {};
    const auto fold = [ & ]( std::string_view name, const RubyValueType& type )
    {
        const auto [ it, inserted ] = localTypes_.try_emplace( typeKey( wall, name ), type );
        if( !inserted && !( it->second == type ) )
        {
            it->second = {};   // two bindings build different things: untyped in the whole scope
        }
    };
    rubyForEachBinding( n, role, src_, [ & ]( TSNode c ) { fold( pattern::nodeText( c, src_ ), assigns && ts_node_eq( c, left ) ? built : RubyValueType {} ); },
                        [ & ]( std::string_view name ) { fold( name, {} ); } );
}

// a let/subject statement of the group whose frame is on top: what its block builds; a named subject is the group's subject too
inline void RubyBareCallWalk::noteLetType( TSNode letCall, std::string_view name )
{
    const std::uint32_t group = frameSerial_[ scopes_.frames.size() - 1 ];
    const RubyValueType built = rubyValueType( rubyLetValue( letCall ), src_, valueSite() );
    letTypes_[ typeKey( group, name ) ] = built;
    if( fieldChildTextOfKind( letCall, NodeField::Method, "identifier", src_ ).starts_with( "subject" ) )
    {
        letTypes_[ typeKey( group, "subject" ) ] = built;
        explicitSubjects_[ group ]               = built;
    }
}

// an example group's implicit subject: the nearest enclosing group's explicit one — RSpec looks it up through the parent
// groups — else `described_class.new`
inline void RubyBareCallWalk::noteImplicitSubject()
{
    const std::size_t top   = scopes_.frames.size() - 1;
    RubyValueType     built = {};
    bool              found = false;
    for( std::size_t d = top; d > scopes_.frames[ top ].classWall && !found; --d )
    {
        const auto it = explicitSubjects_.find( frameSerial_[ d - 1 ] );
        found         = it != explicitSubjects_.end();
        built         = found ? it->second : built;
    }
    const std::string_view described = found ? std::string_view {} : valueSite().described;
    letTypes_[ typeKey( frameSerial_[ top ], "subject" ) ] = described.empty() ? built : RubyValueType { described, "new", false };
}

// a call whose receiver is typed: a value written in place, a let RSpec runs there, or a local of the scope (read at the end)
inline void RubyBareCallWalk::noteTypedCall( TSNode call )
{
    const TSNode           recv   = fieldChild( call, NodeField::Receiver );
    const std::string_view method = fieldChildTextOfKind( call, NodeField::Method, "identifier", src_ );
    if( ts_node_is_null( recv ) || method.empty() )
    {
        return;
    }
    const std::uint32_t at    = ts_node_start_byte( call );
    const bool          ident = kindIs( ts_node_type( recv ), "identifier" );
    if( !ident || !scopes_.visible( pattern::nodeText( recv, src_ ) ) )
    {
        // a value — or a bare word no local or let binds, which is a call on self (`is_expected`)
        const RubyValueType built = rubyValueType( recv, src_, valueSite() );
        if( !built.type.empty() )
        {
            typedSites_.push_back( RubyTypedSite { at, method, ident, built, 0, {} } );
        }
        return;
    }
    noteNamedReceiver( at, method, pattern::nodeText( recv, src_ ) );
}

// a call whose receiver is the bare name `name`: the innermost definition of it visible here — a let, or a local of this
// scope (whose type is read at the end, once every binding is seen) — decides, typed or not
inline void RubyBareCallWalk::noteNamedReceiver( std::uint32_t at, std::string_view method, std::string_view name )
{
    const auto it = scopes_.names.find( name );
    if( it == scopes_.names.end() )
    {
        return;   // no binding: a call on self, which no let or local types
    }
    const RubyLocalScopes::Frame& top = scopes_.frames.back();
    const auto visible = std::find_if( it->second.rbegin(), it->second.rend(),
                                       [ & ]( const RubyLocalScopes::Entry& e ) { return e.depth < top.classWall || e.let || e.depth >= top.wall; } );
    if( visible == it->second.rend() || visible->depth < top.classWall )
    {
        return;
    }
    const bool          local = !visible->let;
    const std::uint32_t frame = frameSerial_[ local ? top.wall : visible->depth ];
    const auto&         table = local ? localTypes_ : letTypes_;
    const auto          found = table.find( typeKey( frame, name ) );
    if( found != table.end() && !found->second.type.empty() )
    {
        typedSites_.push_back( RubyTypedSite { at, method, true, found->second, frame, local ? name : std::string_view {} } );
    }
}

// Each typed site's local read now that every binding is seen, then each written into the call reference the tags query
// made for it — the one in [firstRef, endRef) at the call's start, with its method, whose receiver kind is the site's
// (an identifier receiver is NamedVar, a value receiver FieldOfVar).
inline void RubyBareCallWalk::typeReceivers( std::size_t firstRef, std::size_t endRef )
{
    for( RubyTypedSite& site : typedSites_ )
    {
        if( !site.local.empty() )
        {
            const auto it = localTypes_.find( typeKey( site.wall, site.local ) );
            site.type     = it == localTypes_.end() ? RubyValueType {} : it->second;
        }
    }
    std::erase_if( typedSites_, []( const RubyTypedSite& site ) { return site.type.type.empty(); } );
    std::stable_sort( typedSites_.begin(), typedSites_.end(), []( const RubyTypedSite& a, const RubyTypedSite& b ) { return a.callStart < b.callStart; } );
    for( std::size_t i = firstRef; i < endRef && i < refs_.size() && !typedSites_.empty(); ++i )
    {
        if( const RubyTypedSite* site = siteOf( refs_[ i ] ) )
        {
            rubyTypeReceiver( refs_[ i ], site->type.type, site->type.via, site->type.factory );
        }
    }
}

// A declaration's method symbols (the section note above): a callback macro's at class-body position, each a call
// reference at its symbol; a `send`-family call's symbol, recorded for sendTargets
inline void RubyBareCallWalk::noteDeclaredCall( TSNode call )
{
    const std::string_view        m    = fieldChildTextOfKind( call, NodeField::Method, "identifier", src_ );
    const bool                    bare = ts_node_is_null( fieldChild( call, NodeField::Receiver ) );
    const RubyLocalScopes::Frame& top  = scopes_.frames.back();
    const RubyDeclared            kind = bare && top.wall == top.classWall ? rubyDeclaredKind( m ) : RubyDeclared::None;
    if( kind != RubyDeclared::None )
    {
        rubyForEachDeclaredSymbol( call, kind, src_, [ & ]( TSNode sym )
        {
            const std::string_view text = pattern::nodeText( sym, src_ );
            refs_.push_back( rawRefAt( sym, fileId_, Lang::Ruby, RefRole::Call, std::string( text.substr( text.empty() ? 0 : 1 ) ) ) );
        } );
        return;
    }
    if( !m.empty() && std::ranges::find( kRubySendCalls, m ) != std::end( kRubySendCalls ) )
    {
        const TSNode args  = fieldChild( call, NodeField::Arguments );
        const TSNode first = ts_node_is_null( args ) ? args : ts_node_named_child( args, 0 );
        if( !ts_node_is_null( first ) && kindIs( ts_node_type( first ), "simple_symbol" ) )
        {
            sendSites_.push_back( RubySendSite { ts_node_start_byte( call ), m, first } );
        }
    }
}

// Each `send`-family call's named method, as a call on the same receiver: a copy of the call's own reference — the one
// in [firstRef, endRef) at the call's start that names it, typed receiver and all — renamed and placed at the symbol. Two
// same-named calls starting at one byte (`a.send( :x ).send( :y )`) are ambiguous, and neither is copied.
inline void RubyBareCallWalk::sendTargets( std::size_t firstRef, std::size_t endRef )
{
    std::stable_sort( sendSites_.begin(), sendSites_.end(), []( const RubySendSite& a, const RubySendSite& b ) { return a.callStart < b.callStart; } );
    const auto byStart = []( const RubySendSite& site, std::uint32_t at ) { return site.callStart < at; };
    for( std::size_t i = firstRef; i < endRef && i < refs_.size() && !sendSites_.empty(); ++i )
    {
        const RawRef& r = refs_[ i ];
        for( auto site = std::lower_bound( sendSites_.begin(), sendSites_.end(), r.startByte, byStart );
             r.role == RefRole::Call && site != sendSites_.end() && site->callStart == r.startByte; ++site )
        {
            site->ref = site->method == r.name ? i : site->ref;
            site->hits += site->method == r.name ? 1u : 0u;
        }
    }
    for( const RubySendSite& site : sendSites_ )
    {
        if( site.hits == 1 )
        {
            RawRef                 copy = refs_[ site.ref ];
            const std::string_view text = pattern::nodeText( site.symbol, src_ );
            copy.name.assign( text.substr( text.empty() ? 0 : 1 ) );
            copy.startByte = ts_node_start_byte( site.symbol );
            copy.line      = ts_node_start_point( site.symbol ).row + 1;
            refs_.push_back( std::move( copy ) );
        }
    }
}

// the typed site a call reference was made for: the one at its start whose method it names (a setter `x.name =` names
// `name=`) and whose receiver kind it records — an (identifier) receiver is NamedVar, a value receiver FieldOfVar
inline const RubyTypedSite* RubyBareCallWalk::siteOf( const RawRef& r ) const
{
    const bool ident = r.recv == RecvKind::NamedVar;
    if( r.lang != Lang::Ruby || r.role != RefRole::Call || ( !ident && r.recv != RecvKind::FieldOfVar ) )
    {
        return nullptr;
    }
    const std::string_view name = r.name;
    const std::string_view bare = name.ends_with( '=' ) ? name.substr( 0, name.size() - 1 ) : name;
    const auto byStart = []( const RubyTypedSite& site, std::uint32_t at ) { return site.callStart < at; };
    for( auto site = std::lower_bound( typedSites_.begin(), typedSites_.end(), r.startByte, byStart );
         site != typedSites_.end() && site->callStart == r.startByte; ++site )
    {
        if( site->identReceiver == ident && ( site->method == name || site->method == bare ) )
        {
            return &*site;
        }
    }
    return nullptr;
}

// One file's bare-word calls, and the type of each call receiver the file builds — written into the file's references
// already in `refs` (the tags query's: the trailing run carrying this fileId); the walk's own references follow them.
inline void captureRubyBareCalls( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawRef>& refs )
{
    const std::size_t queryRefsEnd = refs.size();
    std::size_t       firstRef     = queryRefsEnd;
    while( firstRef > 0 && refs[ firstRef - 1 ].fileId == fileId )
    {
        --firstRef;
    }
    RubyBareCallWalk walk( fileId, src, refs );
    walk.run( root );
    walk.typeReceivers( firstRef, queryRefsEnd );
    walk.sendTargets( firstRef, queryRefsEnd );
}

// ─── A Jbuilder template's `json`, and `helper_method` (test/rubyrakejbuildercheck.sh, parser version 135) ─────────────
// graph.h RubyTopSelf reads a template's self outside any class as the view. The template handler binds `json` there to the
// view's JbuilderTemplate (model.h kJbuilderTemplate), whose method_missing makes every name a key: a read of it is no
// call, and a call on it is typed that class. A `helper_method :a, :b` at class-body position names methods of the class
// its views call, recorded as LocalBindKind::RubyHelperMethod bindings against the declaring class or module (a concern's
// `included do` block declares for the concern, whose def it is).

// Over a template's references — the trailing run carrying this fileId: the bare-word `json` reads dropped, and each call
// on `json` typed JbuilderTemplate.
inline void typeRubyJbuilderLocal( std::uint32_t fileId, std::vector<RawRef>& refs )
{
    std::size_t first = refs.size();
    while( first > 0 && refs[ first - 1 ].fileId == fileId )
    {
        --first;
    }
    const auto read = []( const RawRef& r ) { return r.role == RefRole::Call && r.recv == RecvKind::None && r.name == kJbuilderLocal; };
    refs.erase( std::remove_if( refs.begin() + std::ptrdiff_t( first ), refs.end(), read ), refs.end() );
    for( std::size_t i = first; i < refs.size(); ++i )
    {
        if( refs[ i ].role == RefRole::Call && refs[ i ].recv == RecvKind::NamedVar && refs[ i ].recvVar == kJbuilderLocal )
        {
            rubyTypeReceiver( refs[ i ], kJbuilderTemplate, kJbuilderLocal, false );
        }
    }
}

// Does `call` sit at class-body position — its nearest enclosing def-or-class a class or module, any blocks between?
inline bool rubyAtClassBody( TSNode call ) noexcept
{
    for( TSNode p = ts_node_parent( call ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( kindIs( t, "class" ) || kindIs( t, "module" ) )
        {
            return true;
        }
        if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) || kindIs( t, "singleton_class" ) )
        {
            return false;
        }
    }
    return false;
}

// One binding per symbol argument in `args` (`helper_method :a, :b`, `attr_accessor :c`): `like` with the symbol's own start
// byte and its name (the colon dropped).
inline void rubyNoteSymbolArguments( TSNode args, const RawBind& like, std::string_view src, std::vector<RawBind>& binds )
{
    if( ts_node_is_null( args ) )
    {
        return;
    }
    ChildCursor cursor( args );   // O(children) (src/infra/tschildren.h)
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        if( kindIs( ts_node_type( a ), "simple_symbol" ) )
        {
            RawBind b   = like;
            b.startByte = ts_node_start_byte( a );
            b.var       = std::string( pattern::nodeText( a, src ).substr( 1 ) );
            binds.push_back( std::move( b ) );
        }
        return true;
    } );
}

// Each symbol of the `helper_method` call `call`, a binding against the class or module around it.
inline void rubyNoteHelperMethods( TSNode call, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const std::string owner = rubyEnclosingScopeOf( call, src );
    if( !owner.empty() )
    {
        rubyNoteSymbolArguments( fieldChild( call, NodeField::Arguments ),
                                 RawBind { .fileId = fileId, .lang = Lang::Ruby, .kind = LocalBindKind::RubyHelperMethod, .typeName = owner }, src, binds );
    }
}

// Every node of a Ruby file's tree, handed to `take` in turn; a node `take` returns true for is taken, and its subtree is
// not walked. Iterative, so a hostile nesting depth costs heap, not stack.
template<class Take>
inline void rubyWalkUntaken( TSNode root, Take&& take )
{
    std::vector<TSNode> stack { root };
    std::vector<TSNode> kids;
    ChildCursor         cursor( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        if( !take( n ) )
        {
            collectChildren( n, cursor.cur, kids );
            stack.insert( stack.end(), kids.begin(), kids.end() );
        }
    }
}

// One file's `helper_method` declarations, into `binds` — a file that never spells the word is not walked (rubyWalkUntaken).
inline void captureRubyHelperMethods( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "helper_method" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const bool declares = kindIs( ts_node_type( n ), "call" ) && ts_node_is_null( fieldChild( n, NodeField::Receiver ) )
                           && fieldChildTextOfKind( n, NodeField::Method, "identifier", src ) == "helper_method";
        if( declares && rubyAtClassBody( n ) )
        {
            rubyNoteHelperMethods( n, fileId, src, binds );
            return true;
        }
        return false;
    } );
}

// Parser version 137 (test/rubyclassrecvcheck.sh): is the Ruby def `defNode` a SINGLETON method — `def self.m`, or a def
// inside `class << self` — which a call on a class object answers and no instance's lookup reaches? The nearest class,
// module or def above a plain `def` decides; a block between them (`class_methods do`, `included do`) is walked through.
// rubyDefSide below tells whose class object; captureRubyClassMixins reads a directive in `class << self` with this.
inline bool rubyIsSingletonDef( TSNode defNode ) noexcept
{
    if( kindIs( ts_node_type( defNode ), "singleton_method" ) )
    {
        const TSNode object = fieldChild( defNode, NodeField::Object );
        return !ts_node_is_null( object ) && kindIs( ts_node_type( object ), "self" );
    }
    for( TSNode n = ts_node_parent( defNode ); !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "singleton_class" ) )
        {
            const TSNode value = fieldChild( n, NodeField::Value );
            return !ts_node_is_null( value ) && kindIs( ts_node_type( value ), "self" );
        }
        if( kindIs( t, "class" ) || kindIs( t, "module" ) || kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            return false;
        }
    }
    return false;
}

// What a Ruby def is to a class object (parser versions 137 and 145; test/rubyclassrecvcheck.sh).
enum class RubyDefSide : std::uint8_t
{
    Instance,    // an instance method: no call on a class object reaches it
    Singleton,   // a singleton method of the class or module that holds it — `def self.m`, a def or an accessor in `class << self`
    Includer,    // a class method of each class INCLUDING its module, defined on the includer itself: a singleton def inside a
                 //   concern's `included do`, which runs on the includer
    ClassMethods,   // a class method of each includer from a module extended onto it: a def inside a concern's `class_methods
                    //   do`, which ActiveSupport::Concern makes the concern's ClassMethods
};

// The two blocks of an ActiveSupport::Concern whose defs can be its includer's class methods (RubyDefSide::Includer,
// ClassMethods).
inline constexpr std::array<std::string_view, 2> kRubyIncluderBlocks = { "included", "class_methods" };

// The concern hook (kRubyIncluderBlocks) whose block `n` is, written at class-body level, or empty.
inline std::string_view rubyIncluderHook( TSNode n, std::string_view src ) noexcept
{
    const TSNode owner = kindIs( ts_node_type( n ), "do_block" ) || kindIs( ts_node_type( n ), "block" ) ? ts_node_parent( n ) : TSNode {};
    if( ts_node_is_null( owner ) || !kindIs( ts_node_type( owner ), "call" ) )
    {
        return {};
    }
    const std::string_view hook = rubyNamedDirective( owner, src, kRubyIncluderBlocks );
    return !hook.empty() && rubyAttrAtClassBodyLevel( owner, src ) ? hook : std::string_view {};
}

// What a def written in a concern's `hook` block is: in `included do`, a singleton def is the includer's own and a plain
// one an instance method; in `class_methods do`, a plain def is the includer's class method.
inline RubyDefSide rubyHookSide( std::string_view hook, bool singleton ) noexcept
{
    if( hook == "included" )
    {
        return singleton ? RubyDefSide::Includer : RubyDefSide::Instance;
    }
    return singleton ? RubyDefSide::Instance : RubyDefSide::ClassMethods;
}

// What the Ruby def — or `class << self` accessor — at `defNode` is to a class object. A `def self.m`, or a `class << self`
// above it, makes it a singleton method, and the nearest class, module or def above decides whose — unless a concern's
// `included do` (for a singleton def) or `class_methods do` (for a plain one) at class-body level comes first, which makes
// it the includer's: defined on the includer itself, or in the module the concern extends onto it. Any other block between
// is walked through.
inline RubyDefSide rubyDefSide( TSNode defNode, std::string_view src ) noexcept
{
    const bool selfDef = kindIs( ts_node_type( defNode ), "singleton_method" );
    if( selfDef && fieldChildTextOfKind( defNode, NodeField::Object, "self", src ).empty() )
    {
        return RubyDefSide::Instance;   // `def obj.m` is another object's
    }
    bool singleton = selfDef;
    for( TSNode n = ts_node_parent( defNode ); !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "singleton_class" ) )
        {
            if( fieldChildTextOfKind( n, NodeField::Value, "self", src ).empty() )
            {
                return RubyDefSide::Instance;   // `class << Other` opens another object's singleton
            }
            singleton = true;
            continue;
        }
        if( kindIs( t, "class" ) || kindIs( t, "module" ) || kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            break;
        }
        if( const std::string_view hook = rubyIncluderHook( n, src ); !hook.empty() )
        {
            return rubyHookSide( hook, singleton );
        }
    }
    return singleton ? RubyDefSide::Singleton : RubyDefSide::Instance;
}

// The importedName a Ruby class-object binding carries for a def on `side` (model.h LocalBindKind::RubySingletonDef).
inline std::string rubySideMark( RubyDefSide side )
{
    return std::string( side == RubyDefSide::Includer ? kRubyIncluderMark : side == RubyDefSide::ClassMethods ? kRubyClassMethodsMark : std::string_view {} );
}

// A LocalBindKind::RubySingletonDef binding for the def at `defNode` named `name`, when a class object answers it: a
// singleton method (parser version 137), or a class method of each includer (parser version 145).
inline void rubyNoteClassSideDef( TSNode defNode, std::uint32_t fileId, std::string_view name, std::string_view src, std::vector<RawBind>& binds )
{
    const RubyDefSide side = rubyDefSide( defNode, src );
    if( side != RubyDefSide::Instance )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( defNode ), .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef,
                                   .var = std::string( name ), .importedName = rubySideMark( side ) } );
    }
}

// The bindings for what the `class << self` call `n` declares on the class object's `side` — an accessor, or a
// delegation-DSL call (captureRubySingletonAccessors below). An accessor's binding sits at its symbol,
// where captureRubyAttrDefs starts its def (no owner), and carries the side's mark (one a concern's `included do`
// declares is the includer's); a delegated name has no def, and is read against the class that owns the singleton.
inline void rubyNoteSingletonDecl( TSNode n, RubyDefSide side, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const std::string_view delegation = rubyNamedDirective( n, src, kRubyDelegationCalls );
    if( delegation.empty() )
    {
        rubyNoteSymbolArguments( fieldChild( n, NodeField::Arguments ),
                                 RawBind { .fileId = fileId, .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef, .importedName = rubySideMark( side ) },
                                 src, binds );
        return;
    }
    const std::string owner = rubyEnclosingScopeOf( n, src );
    if( delegation == "delegate_missing_to" )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( n ), .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef, .typeName = owner } );
        return;
    }
    rubyNoteSymbolArguments( fieldChild( n, NodeField::Arguments ), RawBind { .fileId = fileId, .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef, .typeName = owner },
                             src, binds );
}

// What a `class << self` declares beside its defs is the class object's too (parser version 137): each accessor
// (`attr_accessor :config`, one RubySingletonDef binding per name, where captureRubyAttrDefs starts its def) and each name
// the delegation DSL defines (model.h kRubyDelegationCalls — `delegate :reset, to: :instance`: a binding per name against
// the owning class; `delegate_missing_to` one with no name, as it answers every name). A file that never writes `<<` is not
// walked; the walk is iterative, so a hostile nesting depth costs heap, not stack.
inline void captureRubySingletonAccessors( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "<<" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const bool        call     = kindIs( ts_node_type( n ), "call" );
        const bool        declares = call && ( !rubyNamedDirective( n, src, kRubyAttrFamilyNames ).empty() || !rubyNamedDirective( n, src, kRubyDelegationCalls ).empty() );
        const RubyDefSide side     = declares && rubyAttrAtClassBodyLevel( n, src ) ? rubyDefSide( n, src ) : RubyDefSide::Instance;
        if( side == RubyDefSide::Instance )
        {
            return false;
        }
        rubyNoteSingletonDecl( n, side, fileId, src, binds );
        return true;
    } );
}

// Parser version 145 (test/rubyclassrecvcheck.sh): each mixin the CLASS OBJECT's lookup reaches rather than its
// instances' — the constants of an `extend M`, and of an `include`/`prepend` inside `class << self` — as a
// LocalBindKind::RubyClassMixin binding at the constant's own start byte, where captureRubyMixinBases puts its inherit
// reference, read where that reads the directive (class-body level, or a concern's `included do`). One a concern's
// `included do` writes extends the includer, not the concern: importedName kRubyIncluderMark. A class body's `extend self`
// names no constant: its binding sits at the directive, var "self". A file that never writes `extend` or `<<` is not
// walked, and the walk enters no def, whose body holds no directive.
// Is the mixin directive `n` an `extend self` — its one argument `self`?
inline bool rubyExtendsSelf( TSNode n ) noexcept
{
    const TSNode args = fieldChild( n, NodeField::Arguments );
    return !ts_node_is_null( args ) && ts_node_named_child_count( args ) == 1 && kindIs( ts_node_type( ts_node_named_child( args, 0 ) ), "self" );
}

// The RubyClassMixin bindings of the mixin directive `n` (an `extend` when `extend`), read where captureRubyMixinBases reads
// it: one per constant a class object's lookup reaches, and a module body's `extend self`.
inline void rubyNoteClassMixins( TSNode n, bool extend, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const bool inIncluded = rubyInConcernIncludedBlock( n, src );
    if( !inIncluded && !rubyAttrAtClassBodyLevel( n, src ) )
    {
        return;
    }
    const bool singleton = rubyIsSingletonDef( n );   // the directive sits in `class << self`
    if( extend && !inIncluded && !singleton && rubyExtendsSelf( n ) )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( n ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyClassMixin, .var = "self" } );
    }
    if( extend == singleton )
    {
        return;   // an include joins the instances' lookup, an extend inside `class << self` the singleton's own
    }
    const bool includer = inIncluded || ( singleton && rubyDefSide( n, src ) == RubyDefSide::Includer );
    for( const TSNode c : rubyMixinTargets( n, src ) )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( c ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyClassMixin,
                                   .importedName = includer ? std::string( kRubyIncluderMark ) : std::string {} } );
    }
}

inline void captureRubyClassMixins( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "extend" ) == std::string_view::npos && src.find( "<<" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            return true;   // a def body holds no directive
        }
        const std::string_view verb = kindIs( t, "call" ) ? rubyNamedDirective( n, src, kRubyConstantDirectives ) : std::string_view {};
        if( verb.empty() || verb == "autoload" )
        {
            return false;
        }
        rubyNoteClassMixins( n, verb == "extend", fileId, src, binds );
        return true;
    } );
}

// ─── FactoryBot's factory definitions (parser version 132, test/rubytypedrecvcheck.sh) ─────────────────────────────────
// `factory :user do … end` inside a `FactoryBot.define` (or `FactoryGirl.define`) block defines what `create( :user )`
// builds, and its class is FactoryBot's own rule: the `class:` option as written — a constant, or a string naming one (its
// final segment) — else the enclosing factory's (a nested factory builds its parent's class), else the `parent:` factory's
// when the file defined it above, else the name camelised (`:user_profile` → UserProfile). One RubyFactory binding per name
// and per `aliases:` entry; graph.h rubyFactoryClasses joins them over the tree, where two classes for one name type nothing.
// A `class:` of any other spelling (a symbol, an expression) records no factory: its class is not known.

// `user_profile` → UserProfile, `admin/user` → User: the final segment of the constant FactoryBot camelises the name into
inline std::string rubyFactoryDefaultClass( std::string_view name )
{
    const std::size_t slash = name.rfind( '/' );
    std::string       out;
    bool              upper = true;
    for( const char c : name.substr( slash == std::string_view::npos ? 0 : slash + 1 ) )
    {
        if( c == '_' )
        {
            upper = true;
            continue;
        }
        out.push_back( upper && c >= 'a' && c <= 'z' ? char( c - 'a' + 'A' ) : c );
        upper = false;
    }
    return out;
}

// The value of the `key:` option among a call's arguments (`class: "User"`, `parent: :user`), or null.
inline TSNode rubyCallOption( TSNode call, std::string_view key, std::string_view src )
{
    const TSNode args = fieldChild( call, NodeField::Arguments );
    TSNode       value {};
    if( !ts_node_is_null( args ) )
    {
        ChildCursor cursor( args );
        forEachNamedChild( args, cursor.cur, [ & ]( TSNode c )
        {
            const TSNode k     = kindIs( ts_node_type( c ), "pair" ) ? fieldChild( c, NodeField::Key ) : TSNode {};
            const bool   named = !ts_node_is_null( k ) && kindIs( ts_node_type( k ), "hash_key_symbol" ) && pattern::nodeText( k, src ) == key;
            value              = named ? fieldChild( c, NodeField::Value ) : value;
            return !named;
        } );
    }
    return value;
}

// The class a `class:` option names: a constant's final segment, or a plain string's (`"Admin::User"` → User); else empty.
inline std::string_view rubyFactoryClassOption( TSNode value, std::string_view src )
{
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    if( isRubyConstantNode( value ) )
    {
        return rubyFinalConstant( value, src );
    }
    if( !kindIs( ts_node_type( value ), "string" ) || ts_node_named_child_count( value ) != 1
        || !kindIs( ts_node_type( ts_node_named_child( value, 0 ) ), "string_content" ) )
    {
        return {};
    }
    const std::string_view text = pattern::nodeText( ts_node_named_child( value, 0 ), src );
    const std::size_t      cut  = text.rfind( "::" );
    return cut == std::string_view::npos ? text : text.substr( cut + 2 );
}

class RubyFactoryWalk
{
public:
    RubyFactoryWalk( std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds ) : fileId_( fileId ), src_( src ), binds_( binds ) {}
    void run( TSNode root );

private:
    struct Item
    {
        TSNode        node;
        bool          inDefine;   // inside a `FactoryBot.define` block
        std::uint32_t parent;     // index into classes_ of the enclosing factory's class; kNone outside one
    };
    static constexpr std::uint32_t kNone = 0xFFFFFFFFu;
    void define( TSNode call, const Item& item );
    std::string classOf( TSNode call, std::string_view name, const Item& item ) const;
    void emit( TSNode call, std::string_view name, const std::string& cls );

    std::uint32_t                    fileId_;
    std::string_view                 src_;
    std::vector<RawBind>&            binds_;
    std::vector<Item>                stack_;
    std::vector<TSNode>              kids_;
    std::vector<std::string>         classes_;
    HashMap<std::string_view, std::uint32_t> byName_;   // a factory defined above in this file → its class
};

inline void RubyFactoryWalk::run( TSNode root )
{
    ChildCursor cursor( root );
    stack_.push_back( Item { root, false, kNone } );
    while( !stack_.empty() )
    {
        Item item = stack_.back();
        stack_.pop_back();
        const TSNode n = item.node;
        if( kindIs( ts_node_type( n ), "call" ) )
        {
            const TSNode           recv = fieldChild( n, NodeField::Receiver );
            const std::string_view on   = !ts_node_is_null( recv ) && isRubyConstantNode( recv ) ? rubyFinalConstant( recv, src_ ) : std::string_view {};
            const std::string_view m    = fieldChildTextOfKind( n, NodeField::Method, "identifier", src_ );
            item.inDefine = item.inDefine || ( ( on == "FactoryBot" || on == "FactoryGirl" ) && m == "define" );
            if( item.inDefine && ts_node_is_null( recv ) && m == "factory" )
            {
                define( n, item );
                continue;
            }
        }
        collectChildren( n, cursor.cur, kids_ );
        for( std::size_t i = kids_.size(); i > 0; --i )
        {
            stack_.push_back( Item { kids_[ i - 1 ], item.inDefine, item.parent } );
        }
    }
}

// one `factory :name, …` call: its class (the section note above), a binding per name and alias, then its block's
// factories, which build this class unless they say otherwise
inline void RubyFactoryWalk::define( TSNode call, const Item& item )
{
    const std::string_view name = rubyFirstSymbolArgument( call, src_ );
    std::string            cls  = name.empty() ? std::string {} : classOf( call, name, item );
    if( cls.empty() )
    {
        return;   // no symbol name, or a class this file does not say: no factory is recorded, and none nested in it
    }
    const std::uint32_t index = std::uint32_t( classes_.size() );
    classes_.push_back( std::move( cls ) );
    byName_.try_emplace( name, index );
    emit( call, name, classes_[ index ] );
    if( const TSNode aliases = rubyCallOption( call, "aliases", src_ ); !ts_node_is_null( aliases ) && kindIs( ts_node_type( aliases ), "array" ) )
    {
        ChildCursor cursor( aliases );
        forEachNamedChild( aliases, cursor.cur, [ & ]( TSNode a )
        {
            const std::string_view alias = kindIs( ts_node_type( a ), "simple_symbol" ) ? pattern::nodeText( a, src_ ).substr( 1 ) : std::string_view {};
            if( !alias.empty() )
            {
                emit( call, alias, classes_[ index ] );
            }
            return true;
        } );
    }
    if( const TSNode block = rubyCallBlock( call ); !ts_node_is_null( block ) )
    {
        stack_.push_back( Item { block, true, index } );
    }
}

// the class `factory :name, …` builds, by FactoryBot's rule (the section note above); empty when this file does not say
inline std::string RubyFactoryWalk::classOf( TSNode call, std::string_view name, const Item& item ) const
{
    if( const TSNode opt = rubyCallOption( call, "class", src_ ); !ts_node_is_null( opt ) )
    {
        return std::string( rubyFactoryClassOption( opt, src_ ) );
    }
    if( const TSNode parent = rubyCallOption( call, "parent", src_ ); !ts_node_is_null( parent ) )
    {
        const bool symbol = kindIs( ts_node_type( parent ), "simple_symbol" );
        const auto named  = symbol ? byName_.find( pattern::nodeText( parent, src_ ).substr( 1 ) ) : byName_.end();
        return named == byName_.end() ? std::string {} : classes_[ named->second ];
    }
    return item.parent != kNone ? classes_[ item.parent ] : rubyFactoryDefaultClass( name );
}

inline void RubyFactoryWalk::emit( TSNode call, std::string_view name, const std::string& cls )
{
    RawBind b;
    b.fileId    = fileId_;
    b.startByte = ts_node_start_byte( call );
    b.lang      = Lang::Ruby;
    b.kind      = LocalBindKind::RubyFactory;
    b.var       = std::string( name );
    b.typeName  = cls;
    binds_.push_back( std::move( b ) );
}

// One file's FactoryBot factories, into `binds` — a file with no `FactoryBot.define` / `FactoryGirl.define` is not walked.
inline void captureRubyFactories( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "FactoryBot.define" ) != std::string_view::npos || src.find( "FactoryGirl.define" ) != std::string_view::npos )
    {
        RubyFactoryWalk( fileId, src, binds ).run( root );
    }
}

// `described_class::Worker` — a constant path whose head is RSpec's described_class — spelled through the path the
// described class is written as (`Log::Worker`, parser version 137); empty for any other head, and where the file
// redefines described_class or a local of that name reaches the head.
inline std::string rubyDescribedRelativePath( TSNode node, std::string_view src )
{
    TSNode head = node;
    for( TSNode scope = fieldChild( head, NodeField::Scope ); kindIs( ts_node_type( head ), "scope_resolution" ) && !ts_node_is_null( scope );
         scope = fieldChild( head, NodeField::Scope ) )
    {
        head = scope;   // the leftmost segment, one step at a time: a deep chain costs a loop, never a frame
    }
    const bool described = kindIs( ts_node_type( head ), "identifier" ) && pattern::nodeText( head, src ) == "described_class"
                        && !rubyDefinesDescribedClassMethod( src ) && !rubyDescribedClassIsLocal( head, src );
    const std::string_view path = described ? rspecDescribedPath( head, src ) : std::string_view {};
    if( path.empty() )
    {
        return {};
    }
    return std::string( path ).append( pattern::nodeText( node, src ).substr( ts_node_end_byte( head ) - ts_node_start_byte( node ) ) );
}

// nullopt when the node is neither (classifyReceiver's shared arms decide it); otherwise the answer, which is empty for a
// (scope_resolution) whose `name:` is not a (constant).
inline std::optional<RecvShape> classifyRubyReceiver( TSNode node, std::string_view src )
{
    const char* rt = ts_node_type( node );
    if( kindIs( rt, "self" ) )
    {
        return RecvShape { RecvKind::ThisObj, {}, {} }; // Ruby `self` — its own node kind, not an identifier
    }
    if( kindIs( rt, "identifier" ) && pattern::nodeText( node, src ) == "described_class" )
    {
        const bool             redefined = rubyDefinesDescribedClassMethod( src ) || rubyDescribedClassIsLocal( node, src );
        const std::string_view cls       = redefined ? std::string_view {} : rspecDescribedClass( node, src );
        if( cls.empty() )
        {
            return std::nullopt;   // redefined, or no constant-described group encloses it: the identifier arm answers as before
        }
        return RecvShape { RecvKind::NamedVar, std::string( cls ), {} };             // the group's constant — Rule 2c fuel
    }
    if( !isRubyConstantNode( node ) )
    {
        return std::nullopt;
    }
    const std::string_view v = rubyFinalConstant( node, src );
    if( v.empty() )
    {
        return RecvShape {};
    }
    return RecvShape { RecvKind::NamedVar, std::string( v ), {} };                  // Rule 2c fuel
}

inline RecvShape classifyReceiver( TSNode node, Lang lang, std::string_view src, bool allowChain )
{
    const char* rt = ts_node_type( node );
    if( kindIs( rt, "this" ) )
    {
        return { RecvKind::ThisObj, {}, {} }; // C++ `this`
    }
    if( lang == Lang::Ruby )
    {
        if( std::optional<RecvShape> ruby = classifyRubyReceiver( node, src ) )
        {
            return std::move( *ruby );   // `self`, or a class/module constant receiver (classifyRubyReceiver)
        }
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

// TS/JS literal-receiver kinds (issue #163). A member call whose receiver type the syntax already
// proves is a built-in; it must not take the bare-name ladder. Object literals, identifier
// receivers, this, casts, and element-returning links stay RecvKind::None. Do NOT widen
// isMemberAccessNode — every recv==None guard would then see every TS/JS member call.
inline RecvKind jsLiteralKindOf( const char* t ) noexcept
{
    if( kindIs( t, "string" ) || kindIs( t, "template_string" ) )
    {
        return RecvKind::LitString;
    }
    if( kindIs( t, "array" ) )
    {
        return RecvKind::LitArray;
    }
    if( kindIs( t, "regex" ) )
    {
        return RecvKind::LitRegex;
    }
    if( kindIs( t, "number" ) )
    {
        return RecvKind::LitNumber;
    }
    if( kindIs( t, "true" ) || kindIs( t, "false" ) )
    {
        return RecvKind::LitBoolean;
    }
    return RecvKind::None;
}

struct JsLitChainRow
{
    RecvKind    from;
    const char* method;
    RecvKind    to;
};

// Certain (from, method) → result kind. Anything not listed ends certainty (find/at/pop/shift/reduce,
// subscript, non-null !, casts). Keep this table the single place a chain link is decided.
inline RecvKind jsLitChainResult( RecvKind from, std::string_view method ) noexcept
{
    static constexpr JsLitChainRow kRows[] = {
        { RecvKind::LitString,  "charAt",             RecvKind::LitString  },
        { RecvKind::LitString,  "concat",             RecvKind::LitString  },
        { RecvKind::LitString,  "normalize",          RecvKind::LitString  },
        { RecvKind::LitString,  "padEnd",             RecvKind::LitString  },
        { RecvKind::LitString,  "padStart",           RecvKind::LitString  },
        { RecvKind::LitString,  "repeat",             RecvKind::LitString  },
        { RecvKind::LitString,  "replace",            RecvKind::LitString  },
        { RecvKind::LitString,  "replaceAll",         RecvKind::LitString  },
        { RecvKind::LitString,  "slice",              RecvKind::LitString  },
        { RecvKind::LitString,  "split",              RecvKind::LitArray   },
        { RecvKind::LitString,  "substr",             RecvKind::LitString  },
        { RecvKind::LitString,  "substring",          RecvKind::LitString  },
        { RecvKind::LitString,  "toLocaleLowerCase",  RecvKind::LitString  },
        { RecvKind::LitString,  "toLocaleUpperCase",  RecvKind::LitString  },
        { RecvKind::LitString,  "toLowerCase",        RecvKind::LitString  },
        { RecvKind::LitString,  "toString",           RecvKind::LitString  },
        { RecvKind::LitString,  "toUpperCase",        RecvKind::LitString  },
        { RecvKind::LitString,  "trim",               RecvKind::LitString  },
        { RecvKind::LitString,  "trimEnd",            RecvKind::LitString  },
        { RecvKind::LitString,  "trimLeft",           RecvKind::LitString  },
        { RecvKind::LitString,  "trimRight",          RecvKind::LitString  },
        { RecvKind::LitString,  "trimStart",          RecvKind::LitString  },
        { RecvKind::LitString,  "valueOf",            RecvKind::LitString  },
        { RecvKind::LitArray,   "concat",             RecvKind::LitArray   },
        { RecvKind::LitArray,   "copyWithin",         RecvKind::LitArray   },
        { RecvKind::LitArray,   "fill",               RecvKind::LitArray   },
        { RecvKind::LitArray,   "filter",             RecvKind::LitArray   },
        { RecvKind::LitArray,   "flat",               RecvKind::LitArray   },
        { RecvKind::LitArray,   "flatMap",            RecvKind::LitArray   },
        { RecvKind::LitArray,   "join",               RecvKind::LitString  },
        { RecvKind::LitArray,   "map",                RecvKind::LitArray   },
        { RecvKind::LitArray,   "reverse",            RecvKind::LitArray   },
        { RecvKind::LitArray,   "slice",              RecvKind::LitArray   },
        { RecvKind::LitArray,   "sort",               RecvKind::LitArray   },
        { RecvKind::LitArray,   "toLocaleString",     RecvKind::LitString  },
        { RecvKind::LitArray,   "toReversed",         RecvKind::LitArray   },
        { RecvKind::LitArray,   "toSorted",           RecvKind::LitArray   },
        { RecvKind::LitArray,   "toSpliced",          RecvKind::LitArray   },
        { RecvKind::LitArray,   "toString",           RecvKind::LitString  },
        { RecvKind::LitArray,   "with",               RecvKind::LitArray   },
        { RecvKind::LitRegex,   "test",               RecvKind::LitBoolean },
        { RecvKind::LitNumber,  "toExponential",      RecvKind::LitString  },
        { RecvKind::LitNumber,  "toFixed",            RecvKind::LitString  },
        { RecvKind::LitNumber,  "toPrecision",        RecvKind::LitString  },
        { RecvKind::LitNumber,  "toString",           RecvKind::LitString  },
        { RecvKind::LitBoolean, "toString",           RecvKind::LitString  },
    };
    for( const JsLitChainRow& row : kRows )
    {
        if( row.from == from && method == row.method )
        {
            return row.to;
        }
    }
    return RecvKind::None;
}

inline RecvKind classifyJsTsLiteralRecv( TSNode node, std::string_view src, int depth ) noexcept
{
    if( depth > 16 || ts_node_is_null( node ) )
    {
        return RecvKind::None;
    }
    const char* t = ts_node_type( node );
    if( kindIs( t, "parenthesized_expression" ) )
    {
        return classifyJsTsLiteralRecv( ts_node_named_child( node, 0 ), src, depth + 1 );
    }
    // A SIGNED numeric literal — (-1).toFixed(), (+2).toFixed() — is a number receiver: the grammar spells the sign as a
    // unary operator over a `number` node, so without this it classified as no literal at all and the call could bind an
    // unrelated in-repo toFixed. Only + and - over a number: `!1`, `typeof 1` and `-x` are not number literals.
    if( kindIs( t, "unary_expression" ) )
    {
        const TSNode sign = fieldChild( node, NodeField::Operator );
        const TSNode arg  = fieldChild( node, NodeField::Argument );
        if( !ts_node_is_null( sign ) && !ts_node_is_null( arg ) && kindIs( ts_node_type( arg ), "number" ) )
        {
            const std::string_view op = pattern::nodeText( sign, src );
            if( op == "-" || op == "+" )
            {
                return RecvKind::LitNumber;
            }
        }
        return RecvKind::None;
    }
    if( kindIs( t, "as_expression" ) || kindIs( t, "satisfies_expression" )
        || kindIs( t, "type_assertion" ) || kindIs( t, "non_null_expression" )
        || kindIs( t, "subscript_expression" ) )
    {
        return RecvKind::None;
    }
    const RecvKind lit = jsLiteralKindOf( t );
    if( lit != RecvKind::None )
    {
        return lit;
    }
    if( !kindIs( t, "call_expression" ) )
    {
        return RecvKind::None;
    }
    const TSNode fn = fieldChild( node, NodeField::Function );
    if( ts_node_is_null( fn ) || !kindIs( ts_node_type( fn ), "member_expression" ) )
    {
        return RecvKind::None;
    }
    const TSNode prop = fieldChild( fn, NodeField::Property );
    const TSNode obj  = fieldChild( fn, NodeField::Object );
    if( ts_node_is_null( prop ) || ts_node_is_null( obj ) )
    {
        return RecvKind::None;
    }
    const RecvKind inner = classifyJsTsLiteralRecv( obj, src, depth + 1 );
    if( inner == RecvKind::None )
    {
        return RecvKind::None;
    }
    return jsLitChainResult( inner, pattern::nodeText( prop, src ) );
}

// The node a call's @name hangs under once the C++ template-argument wrappers are stepped over. For
// `x.m()` that is the name's own parent. `x.m<T>()` puts ONE wrapper between them — field_expression
// field: (template_method name: m arguments: …) — and the disambiguated `x.template m<T>()` a second —
// field: (dependent_name (template_method …)) — so the climb steps over exactly those two kinds, in that
// order, and a name under any other parent keeps the parent it had. Both kinds are tree-sitter-cpp's (the
// CUDA grammar is generated from it); no other grammar names either, so the climb is inert everywhere else.
// A template_method that is not a member callee (a qualified definition's declarator) climbs to a parent
// that is no member access, which every caller already reads as "not a member call".
inline TSNode calleeAccessParent( TSNode nameNode ) noexcept
{
    TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || !kindIs( ts_node_type( parent ), "template_method" ) )
    {
        return parent;
    }
    parent = ts_node_parent( parent );
    if( !ts_node_is_null( parent ) && kindIs( ts_node_type( parent ), "dependent_name" ) )
    {
        parent = ts_node_parent( parent );
    }
    return parent;
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
// TS/JS: a member_expression whose object is a certain literal (or a chain that stays certain) returns
// LitString/LitArray/LitRegex/LitNumber/LitBoolean instead of None. isMemberAccessNode stays false for
// TS/JS so every other member call is still RecvKind::None.
//
// The parent it inspects is calleeAccessParent's, not the raw parent: a C++ member call with explicit
// template arguments puts a template_method (and, behind `template`, a dependent_name) between the name and
// its field_expression. Read through the raw parent, `other.f<T>()` classified None — a BARE call — and the
// enclosing-class rule pinned it to the caller's own same-named method (test/cppqualcheck.sh §12 (d)).
inline RecvShape receiverOf( TSNode nameNode, Lang lang, std::string_view src )
{
    const TSNode parent = calleeAccessParent( nameNode );
    if( ts_node_is_null( parent ) )
    {
        return {};
    }
    if( const TSNode obj = memberOnlyReceiver( parent, lang ); !ts_node_is_null( obj ) )
    {
        if( lang == Lang::TypeScript || lang == Lang::JavaScript )
        {
            const RecvKind lit = classifyJsTsLiteralRecv( obj, src, 0 );
            if( lit != RecvKind::None )
            {
                return { lit, {}, {} };
            }
        }
        RecvShape member;   // recv stays None (non-literal TS/JS, every Go/Rust member call); FE-A marks the shape
        member.member = true;
        if( lang == Lang::Rust || lang == Lang::C )
        {
            member.root = memberChainRoot( obj, src );   // FE-A's root only: no receiver-evidence rule reads these two
            return member;
        }
        MemberChain chain = memberChainOf( obj, lang, src );   // FE-B: root + path + constructed class
        member.root = std::move( chain.root );
        member.path = std::move( chain.path );
        member.ctor = std::move( chain.ctor );
        return member;
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
    // `p->m()` against `p.m()`: on a std smart pointer member only `->` reaches the pointee (Rule 2b, fieldnarrowcheck arm p)
    rs.viaArrow  = ( lang == Lang::Cpp || lang == Lang::ObjC ) && nodeFieldText( parent, NodeField::Operator, src ) == "->";
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

// The constant a Ruby call's receiver names, AS WRITTEN, when that differs from `final` — the final segment recvVar keeps
// (parser version 137: `Stripe::Customer` is not the tree's Customer unless the tree opens that path, graph.h
// RubyClassObjects). A qualified constant's whole path; the path through the described class for `described_class` and
// for `described_class::Worker`; empty for a final segment alone, and for a path with any other head that is no constant
// (`self.class::Foo`).
inline std::string rubyReceiverWrittenPath( TSNode nameNode, std::string_view final, std::string_view src )
{
    const TSNode call = calleeAccessParent( nameNode );
    const TSNode recv = ts_node_is_null( call ) || !kindIs( ts_node_type( call ), "call" ) ? TSNode {} : fieldChild( call, NodeField::Receiver );
    std::string  written;
    if( ts_node_is_null( recv ) )
    {
        return written;
    }
    if( kindIs( ts_node_type( recv ), "identifier" ) && pattern::nodeText( recv, src ) == "described_class" )
    {
        // The group's path. Also written where classifyRubyReceiver declined (a local or redefined described_class), but
        // never read there: rubyConstantReceiver (graph.h) reads it only beside a constant recvVar, and a declined one keeps
        // `described_class` (test/rubydescribedclasscheck.sh qloc_spec). Not writing it moves extraction output (kParserVer).
        written = rspecDescribedPath( recv, src );
    }
    else if( isRubyConstantNode( recv ) )
    {
        written = rubyIsConstantChain( recv ) ? std::string( pattern::nodeText( recv, src ) ) : rubyDescribedRelativePath( recv, src );
    }
    return written == final ? std::string {} : written;
}

// Java method references are not ordinary member-access nodes. The pinned grammar's first named
// child is the receiver and deliberately uses the SAME `identifier` node for a simple type and a
// variable. Preserve that uncertainty for graph.h: simple and dotted type candidates are retained
// as JavaTypeCandidate with the receiver text (`Widget`, `Outer.Inner`, `com.example.Widget`);
// `this`, `super`, arbitrary expressions, and `Type::new` remain unresolved here. The resolver
// proves a type receiver from indexed class names and lexical shadowing at the site — it does
// not require every dotted segment to be a class (package prefixes are not classes).
// The member-name query already excludes `new`.
inline RecvShape javaMethodReferenceReceiver( TSNode roleNode, std::string_view src )
{
    RecvShape out;
    if( ts_node_is_null( roleNode ) || !kindIs( ts_node_type( roleNode ), "method_reference" ) )
    {
        return out;
    }
    out.kind = RecvKind::JavaTypeCandidate;
    if( ts_node_named_child_count( roleNode ) == 0 )
    {
        return out;
    }
    const TSNode receiver = ts_node_named_child( roleNode, 0 );
    if( kindIs( ts_node_type( receiver ), "identifier" ) )
    {
        out.var = std::string( nodeTextOf( receiver, src ) );
    }
    else if( kindIs( ts_node_type( receiver ), "field_access" ) )
    {
        out.var = std::string( nodeTextOf( receiver, src ) );
    }
    return out;
}

// ── P2-D Rule 2 LOCAL-VARIABLE TYPE BINDING capture (`Foo x;` → x:Foo) ───────────────────────────────
// Walk a node subtree and emit one RawBind per local variable whose TYPE is syntactically decidable, so a
// later `x.m()`/`x->m()` can narrow to `typeName::m`. Pure-syntactic, deterministic, allocation-light:
// it reads exactly the declaration/assignment shapes ground-truthed from the grammars (see the gate fixtures).
//   * The recorded typeName is the WRITTEN type's final segment (`ns::Foo` → `Foo`). Rule 2 matches it as the scope
//     of the called method, so an inferred type from a constructor-call (`auto x = Foo()`) only narrows if `Foo`
//     defines the method; an ASSIGNMENT's inferred type is dropped in buildGraph unless a class of that name exists.
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
// records for `Foo& x = …` locals too, which Rule 2's flat per-function table would leak past their scope
// (ParamType records reach Rule 2 only through the lexical lookup, resolve.h buildScopedRecvDecls).
inline std::string_view paramDeclaratorVarName( TSNode decl, std::string_view src )
{
    if( !ts_node_is_null( decl ) && kindIs( ts_node_type( decl ), "reference_declarator" )
        && ts_node_is_null( fieldChild( decl, NodeField::Declarator ) ) && ts_node_named_child_count( decl ) > 0 )
    {
        decl = ts_node_named_child( decl, 0 );
    }
    return declaratorVarName( decl, src );
}

// the node a C++ type or constructor NAME ends in, read through the grammar's own fields — a qualified name's `name`,
// then a template-id's `name`: `Vec<Decl *>` and `ll::Vec<Decl *>` end in `Vec`, `Outer<int>::Inner` in `Inner`. The
// spelling is never cut as text: finalSegment() truncates at the FIRST `<`, which read `Outer<int>::Inner` as `Outer`
// (test/narrowcheck.sh arm 41). Every other kind is its own last name. Each step moves to a child, so the walk ends; a
// missing `name` field (error recovery) reads as a null node, whose text is "".
inline TSNode lastNameNode( TSNode n ) noexcept
{
    while( !ts_node_is_null( n ) )
    {
        const char* t = ts_node_type( n );
        if( !kindIs( t, "qualified_identifier" ) && !kindIs( t, "template_type" ) && !kindIs( t, "template_function" ) )
        {
            break;
        }
        n = fieldChild( n, NodeField::Name );
    }
    return n;
}

// the type NAME of a constructor-style RHS value node: `Foo()` (call_expression) or `new Foo()`
// (new_expression). Last name of the callee/constructor identifier. "" if the value isn't a
// plain constructor call. A plain FUNCTION call is not told apart: `auto x = makeFoo()` records `makeFoo`, which names
// no class and never narrows (graph.h's varType note) — but it still conflicts with the variable's other declarations
// in Rule 2's flat table, and a conflict tombstones the variable. The assignment `x = makeFoo()` records it too;
// assignedTypeOf marks that one, and buildGraph keeps it only when a class names it (resolve.h assignmentNamesNoClass).
inline TSNode ctorNameNode( TSNode value )
{
    if( ts_node_is_null( value ) )
    {
        return TSNode{};
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
        return TSNode{};
    }
    const char* it = ts_node_type( idn );
    // An unqualified template-id callee (`Vec<T>()`) is refused, a STATED FLOOR (test/narrowcheck.sh arm 39d): the same
    // spelling is every cast helper, and accepting it records `dyn_cast` / `cast` as the type of `auto *CI =
    // dyn_cast<CallInst>( I )` — a name that conflicts with the declaration's written type (`const ConstantInt *CI =
    // dyn_cast<ConstantInt>( V )`) or with a second declaration of the variable, and the conflict tombstones it. Measured on
    // integration/train-3 (llvm-project 4d5358b1d, 2026-09-17): accepting it moves 463 call sites, 324 of them edges lost
    // and 2 gained; rocksdb moves none. (On main, before #278 dropped an ASSIGNMENT's callee name, `Spec =
    // cast<FunctionDecl>( F )` tombstoned too: 994 moved, 779 lost.) The class a cast names
    // is its template ARGUMENT, which a name-only record cannot tell from a constructor's. The QUALIFIED spelling
    // (`llvm::cast<T>( x )`) still records its last name the same way, as it did before this floor was written.
    if( !kindIs( it, "identifier" ) && !kindIs( it, "type_identifier" ) && !kindIs( it, "qualified_identifier" ) && !kindIs( it, "scoped_identifier" ) )
    {
        return TSNode{};
    }
    return idn;
}

inline std::string ctorTypeOf( TSNode value, std::string_view src )
{
    return finalSegment( nodeTextOf( lastNameNode( ctorNameNode( value ) ), src ) );   // a null node reads "", and "" splits to ""
}

// the written type name of a `type:`-field type node — a `type_identifier`, a qualified one or a template-id — as its
// last name (lastNameNode: `Vec<Decl *>` → `Vec`, `Outer<int>::Inner` → `Inner`). "" for `auto`/decltype/dependent
// types — those fall back to constructor inference.
inline std::string writtenTypeOf( TSNode typeNode, std::string_view src )
{
    if( ts_node_is_null( typeNode ) )
    {
        return {};
    }
    const char* tt = ts_node_type( typeNode );
    if( kindIs( tt, "type_identifier" ) || kindIs( tt, "qualified_identifier" ) || kindIs( tt, "template_type" ) )
    {
        return finalSegment( nodeTextOf( lastNameNode( typeNode ), src ) );
    }
    return {};   // auto / decltype / dependent — type not directly written → try the initializer
}

// Rule 2's qualifier guard (2026-09-16, test/narrowcheck.sh arms 17-24): the text of a type or constructor NAME node
// when it is QUALIFIED — a qualified name on its way to the last name has a scope (`std::map<K, V>`, `ext::Widget`,
// `Outer<int>::Inner`; a leading global `::` alone has none) — else "". writtenTypeOf/ctorTypeOf keep the last name
// alone, and Rule 2 matches it against class names that carry no namespace, so `const std::map<K, V>& ref` read as
// `map` and narrowed to an unrelated in-repo `map` (measured on a private C++ corpus). The whole text rides the
// Type/ParamType record in RawBind::importedName; Rule 2 refuses to narrow on a `std::` one (resolve.h namesStdType)
// and keeps every other. A template ARGUMENT's `::` qualifies nothing: `Vec<std::string>` is unqualified (arm 40).
inline std::string qualifiedNameText( TSNode nameNode, std::string_view src )
{
    bool scoped = false;
    for( TSNode n = nameNode; !scoped && !ts_node_is_null( n ) && kindIs( ts_node_type( n ), "qualified_identifier" ); n = fieldChild( n, NodeField::Name ) )
    {
        scoped = !ts_node_is_null( fieldChild( n, NodeField::Scope ) );
    }
    if( !scoped )
    {
        return {};
    }
    std::string_view text = nodeTextOf( nameNode, src );
    while( !text.empty() && ( text.front() == ' ' || text.front() == ':' ) )
    {
        text.remove_prefix( 1 );   // a leading `::` names the global namespace — not a qualifier
    }
    return std::string( text );
}

// one declaration's recorded type: the name Rule 2 matches (the final segment) and, when the type was written
// QUALIFIED, its whole text — carried together so no emitter can record one without the other — and whether an
// ASSIGNMENT's callee supplied it rather than a declaration (assignedTypeOf).
struct DeclType
{
    std::string name;
    std::string qualified;
    bool        isFromAssignment = false;
};

// a type or constructor NAME node's DeclType
inline DeclType declTypeOfName( TSNode typeNode, std::string_view src )
{
    return DeclType{ writtenTypeOf( typeNode, src ), qualifiedNameText( typeNode, src ) };
}

// a declarator's recorded type: the declaration's WRITTEN type when it has one, else the type of the constructor its
// initializer calls (`auto x = Foo()`, `auto x = ns::Foo()`)
inline DeclType declaredTypeOf( const DeclType& written, TSNode value, std::string_view src )
{
    if( !written.name.empty() )
    {
        return written;
    }
    return DeclType{ ctorTypeOf( value, src ), qualifiedNameText( ctorNameNode( value ), src ) };
}

// a C++ ASSIGNMENT's recorded type (`x = Foo()`, `x = new Foo()`): the callee's, marked as an assignment's. The grammar
// cannot tell a constructor from a function here — `t = llvm::cast<Target>( y )` reads `cast` — and an assignment
// declares nothing, so graph.h keeps the record only when a class of that name exists (resolve.h assignmentNamesNoClass).
inline DeclType assignedTypeOf( TSNode value, std::string_view src )
{
    DeclType type = declaredTypeOf( DeclType{}, value, src );
    type.isFromAssignment = true;
    return type;
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
// load-bearing for Rule 2 (an undecidable type must degrade to §2a, not mint a half-record). The DeclType's
// qualified text rides importedName (see qualifiedNameText) — non-empty only on a declaration's Type/ParamType record.
inline void pushTypedBind( std::uint32_t fileId, Lang lang, std::string_view var, DeclType type, BindSite site, LocalBindKind kind,
                           std::vector<RawBind>& binds )
{
    if( var.empty() || ( type.name.empty() && kind != LocalBindKind::VarDecl ) )
    {
        return;
    }
    RawBind b;
    b.fileId       = fileId;
    b.startByte    = site.startByte;
    b.lang         = lang;
    b.kind         = kind;
    b.spanStart    = site.spanStart;
    b.spanEnd      = site.spanEnd;
    b.var.assign( var );
    b.typeName     = std::move( type.name );
    b.importedName = std::move( type.qualified );
    b.isFromAssignment = type.isFromAssignment;
    binds.push_back( std::move( b ) );
}

// the same record with no qualified text — every emitter but a declaration's Type/ParamType
inline void pushRawBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                         BindSite site, LocalBindKind kind, std::vector<RawBind>& binds )
{
    pushTypedBind( fileId, lang, var, DeclType{ std::move( typeName ), std::string{} }, site, kind, binds );
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
        // Java (and Go/Rust) spell a plain brace block `block`. C++ hits compound_statement
        // first, so this arm is inert there. Checked before lambda/method so a body local
        // stays in its block rather than the whole callable.
        if( kindIs( pt, "block" ) )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), true };
        }
        if(    kindIs( pt, "for_statement" ) || kindIs( pt, "for_range_loop" )
            || kindIs( pt, "if_statement" )  || kindIs( pt, "while_statement" )
            || kindIs( pt, "switch_statement" )
            || kindIs( pt, "enhanced_for_statement" ) || kindIs( pt, "catch_clause" )
            || kindIs( pt, "switch_block" ) || kindIs( pt, "try_with_resources_statement" ) )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), false };
        }
        // Java parameters and inferred lambda names: the callable is the scope when no
        // block sits between the declaration and it. C++ lambda bodies are
        // compound_statement, so a C++ local still hits that first.
        if(    kindIs( pt, "lambda_expression" )
            || kindIs( pt, "method_declaration" )
            || kindIs( pt, "constructor_declaration" ) )
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

// the declarator one wrapping declarator holds: its `declarator` field, or, for the three kinds whose grammar rule
// names no field — reference_declarator (`& d`), parenthesized_declarator (`( d )`) and attributed_declarator
// (`d [[maybe_unused]]`) — its first named child. Null for a leaf (an identifier, a qualified name).
inline TSNode innerDeclaratorOf( TSNode decl )
{
    const TSNode inner = fieldChild( decl, NodeField::Declarator );
    if( !ts_node_is_null( inner ) )
    {
        return inner;
    }
    const char* dt = ts_node_type( decl );
    const bool  holdsUnnamed = kindIs( dt, "reference_declarator" ) || kindIs( dt, "parenthesized_declarator" ) || kindIs( dt, "attributed_declarator" );
    return ( holdsUnnamed && ts_node_named_child_count( decl ) > 0 ) ? ts_node_named_child( decl, 0 ) : TSNode{};
}

// r9 shadow fix round (A5): every VARIABLE name a declarator declares → one VarDecl record each, carrying
// the declaring block's span. Handles the shapes the verifier refuted the first landing on:
//   * reference_declarator / parenthesized_declarator hold their inner declarator as an UNNAMED child
//     (no `declarator` field — same grammar fact fnDeclaratorVarName already works around), so a
//     field-only unwrap missed `const T& key` entirely — pass-by-const-ref, the most idiomatic C++
//     parameter shape; attributed_declarator (`int run [[maybe_unused]] = 0;`) is the same fact and
//     recorded nothing until 2026-09-17 (test/shadowcheck.sh arm q8) — all three unwrap in innerDeclaratorOf;
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
        const TSNode inner = innerDeclaratorOf( decl );
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
inline void emitDeclBinds( std::uint32_t fileId, Lang lang, TSNode declNode, std::string_view src, DeclType type,
                           BindSite site, std::vector<RawBind>& binds )
{
    const std::string_view var = declaratorVarName( declNode, src );
    if( var.empty() && !type.name.empty() )
    {
        // member-variable round (card A3): a REFERENCE local (`const Symbol& s = ing.symbols[ i ];`) is the one
        // typed declaration Rule 2's flat table refuses (declaratorVarName cannot see through the unnamed reference
        // child). Recorded as a ParamType fact, so `s.name` resolves in the field use-site index and `s.m()` narrows
        // through Rule 2's LEXICAL lookup (resolve.h buildScopedRecvDecls) — only where this declaration is in scope.
        pushTypedBind( fileId, lang, paramDeclaratorVarName( declNode, src ), std::move( type ), BindSite{ site.startByte, 0u, 0u }, LocalBindKind::ParamType, binds );
    }
    else
    {
        pushTypedBind( fileId, lang, var, std::move( type ), BindSite{ site.startByte, 0u, 0u }, LocalBindKind::Type, binds );
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
        // c:Counter), read by the field use-site index and Rule 2's lexical lookup — see LocalBindKind::ParamType. `auto`, templated
        // and decltype types write nothing (writtenTypeOf's own refusal), and pushRawBind drops the record.
        pushTypedBind( fileId, lang, paramDeclaratorVarName( declarator, src ), declTypeOfName( fieldChild( p, NodeField::Type ), src ),
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
// parameters and a fn-pointer TYPE's parameter list out of shadow evidence. The `T&` / `T&&` step goes
// through innerDeclaratorOf: a reference_declarator holds the function declarator by no field, and a
// field-only walk stopped there, so every definition returning a reference recorded no parameter at all
// (2026-09-17, test/narrowcheck.sh arms 61-63, test/shadowcheck.sh arm am).
inline TSNode fnDefParameterList( TSNode fnDef )
{
    TSNode decl = fieldChild( fnDef, NodeField::Declarator );
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ) && !kindIs( ts_node_type( decl ), "function_declarator" ); ++guard )
    {
        decl = innerDeclaratorOf( decl );
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

// Java issue #74: a parameter or local named like a class is a value receiver for
// Identifier::method, but only where Java lexical scope makes that binding active.
// Class fields keep empty spans and are copied onto contained methods in graph.h.
// Locals start at the declarator (plain block) or the enclosing statement; parameters
// and inferred lambda names cover the callable body.
inline bool javaKindIsFieldDecl( const char* t ) noexcept
{
    return kindIs( t, "field_declaration" ) || kindIs( t, "constant_declaration" );
}

inline bool javaKindIsCallable( const char* t ) noexcept
{
    return kindIs( t, "method_declaration" ) || kindIs( t, "constructor_declaration" )
        || kindIs( t, "lambda_expression" );
}

inline BindSite javaShadowSite( TSNode declNode, TSNode nameNode ) noexcept
{
    const std::uint32_t start = ts_node_start_byte( nameNode );
    TSNode p = ts_node_parent( declNode );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( javaKindIsFieldDecl( pt ) )
        {
            return { start, 0u, 0u };
        }
        if(    kindIs( pt, "block" ) || kindIs( pt, "for_statement" )
            || kindIs( pt, "enhanced_for_statement" ) || kindIs( pt, "switch_block" )
            || kindIs( pt, "catch_clause" ) || kindIs( pt, "try_with_resources_statement" ) )
        {
            break;
        }
        if( javaKindIsCallable( pt ) )
        {
            const TSNode body = fieldChild( p, NodeField::Body );
            if( ts_node_is_null( body ) )
            {
                return { start, ts_node_start_byte( p ), ts_node_end_byte( p ) };
            }
            return { start, ts_node_start_byte( body ), ts_node_end_byte( body ) };
        }
        p = ts_node_parent( p );
    }
    const ShadowScope scope = enclosingShadowScope( declNode );
    return { start, shadowSpanStart( scope, declNode ), scope.end };
}

inline void emitJavaShadowName( std::uint32_t fileId, Lang lang, TSNode declNode, TSNode nameNode,
                               std::string_view src, std::vector<RawBind>& binds )
{
    if( ts_node_is_null( nameNode ) || !kindIs( ts_node_type( nameNode ), "identifier" ) )
    {
        return;
    }
    pushRawBind( fileId, lang, nodeTextOf( nameNode, src ), std::string{},
                 javaShadowSite( declNode, nameNode ), LocalBindKind::VarDecl, binds );
}

inline void captureJavaShadowDecls( TSNode n, const char* t, std::uint32_t fileId, Lang lang,
                                   std::string_view src, std::vector<RawBind>& binds )
{
    // A catch parameter and a try-with-resources `resource` declare a name the same way (a `name:` field; a resource
    // that only NAMES an existing variable has none, and emits nothing). Their scope is the catch clause or the whole
    // try-with-resources statement, which javaShadowSite reaches through enclosingShadowScope.
    if( kindIs( t, "formal_parameter" ) || kindIs( t, "spread_parameter" ) || kindIs( t, "variable_declarator" )
        || kindIs( t, "catch_formal_parameter" ) || kindIs( t, "resource" ) )
    {
        emitJavaShadowName( fileId, lang, n, fieldChild( n, NodeField::Name ), src, binds );
        return;
    }
    // `for ( T x : xs )` — the loop itself declares x, so the NAME is passed as the declaration node: its parent is the
    // loop, whose span is x's scope. Passing the statement would start the walk at the enclosing block and widen the
    // veto to every reference after the loop (test/javamethodrefcheck.sh forEachAfterFn).
    if( kindIs( t, "enhanced_for_statement" ) )
    {
        const TSNode name = fieldChild( n, NodeField::Name );
        emitJavaShadowName( fileId, lang, name, name, src, binds );
        return;
    }
    // `Widget -> ...` — the inferred parameter is the `parameters:` identifier of the lambda.
    if( kindIs( t, "lambda_expression" ) )
    {
        const TSNode params = fieldChild( n, NodeField::Parameters );
        if( !ts_node_is_null( params ) && kindIs( ts_node_type( params ), "identifier" ) )
        {
            emitJavaShadowName( fileId, lang, params, params, src, binds );
        }
        return;
    }
    // `(Widget) -> ...` / `(a, b) -> ...` — inferred_parameters holds identifier children.
    if( kindIs( t, "inferred_parameters" ) )
    {
        const std::uint32_t cc = ts_node_named_child_count( n );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const TSNode c = ts_node_named_child( n, i );
            if( kindIs( ts_node_type( c ), "identifier" ) )
            {
                emitJavaShadowName( fileId, lang, c, c, src, binds );
            }
        }
    }
}

// issue #287 round 2 (Rule 2d soundness, review rv-p6.md HIGH finding): collect every bare NAME a Python
// assignment-target-shaped node binds, at any depth through tuple/list unpacking and a starred target —
// NEVER through an attribute or subscript target (`obj.tm = x` / `d["tm"] = x` mutate an object; they do
// not rebind a NAME). `target` and every node reached through it come straight from the parse tree — a
// shape this function does not recognise (an attribute, a subscript, a malformed unpacking) is refused by
// simply not collecting it, the same graceful skip every sibling capture in this file already uses for an
// unexpected grammar shape, not a promise this function makes about what parsed source contains.
inline void collectPythonNameTargets( TSNode target, std::vector<TSNode>& out )
{
    if( ts_node_is_null( target ) )
    {
        return;
    }
    const char* tt = ts_node_type( target );
    if( kindIs( tt, "identifier" ) )
    {
        out.push_back( target );
        return;
    }
    if( kindIs( tt, "pattern_list" ) || kindIs( tt, "tuple_pattern" ) || kindIs( tt, "list_pattern" ) || kindIs( tt, "expression_list" ) )
    {
        const std::uint32_t cc = ts_node_named_child_count( target );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            collectPythonNameTargets( ts_node_named_child( target, i ), out );
        }
        return;
    }
    if( kindIs( tt, "list_splat_pattern" ) || kindIs( tt, "dictionary_splat_pattern" ) )
    {
        if( ts_node_named_child_count( target ) > 0 )
        {
            collectPythonNameTargets( ts_node_named_child( target, 0 ), out );   // `*rest` / `**rest` — unwrap to the bound name
        }
        return;
    }
    // attribute / subscript / anything else this shape doesn't recognise — not a bare-name rebind.
}

// issue #287 round 2 (Rule 2d soundness, review rv-p6.md HIGH finding). Rule 2d's `hasLocal` guard
// (graph.h ExternalVeto::hasLocal) only sees evidence from a Binding, and Python previously recorded
// NONE for a plain reassignment — only Import (file scope) and a parameter's VarDecl
// (capturePythonParamShadowDecls, just below) ever reached it. So `import target_mod as tm` followed by
// `tm = {"run": …}` inside the SAME function left the reassignment invisible: Rule 2d saw no local
// evidence for `tm` and confidently bound `tm.run(1)` to the import's module after the name had stopped
// meaning that. This closes the gap: every Python name-REBINDING form emits a `LocalBindKind::VarDecl`
// RawBind — the exact "veto evidence only, empty span" shape `capturePythonParamShadowDecls` already
// uses — so a reassignment and a parameter shadow read as the identical fact to Rule 2d's guard.
//
// SCOPE, and why `startByte` alone decides it. `fromSymbol = bindSweep.find( fileId, startByte )`
// (ingest_model.h emitBindings) is the SAME byte-to-enclosing-def sweep every other bind kind already
// rides — nothing new to plumb. A form physically INSIDE a function attributes to that function, so
// `hasLocal` refuses only THAT function's uses of the name — sound, because a plain Python assignment
// with no `global`/`nonlocal` is function-local. A form at true module top level gets NO enclosing def
// (`fromSymbol==kNoNode`) — `buildFieldNarrowTables` already skips `fromSymbol==kNoNode` bindings for
// `hasLocal` on purpose, so these never reach it; `graph.h`'s `pythonModuleRebind` table (built in
// `buildExternalVetoTables`) reads them instead and vetoes the WHOLE FILE's use of the name, because a
// module-global rebind can reach every function that reads it. `global NAME` / `nonlocal NAME` get that
// SAME file-wide treatment ON PURPOSE even when the statement sits inside a function — such a statement
// can rewrite the file's own module global — so it is deliberately recorded at `startByte=0` (guaranteed
// to resolve to no enclosing def) rather than at its own position, which would otherwise only veto the
// one function that happens to declare it.
//
// NEVER GUESS, never over-claim either: comprehension-scoped targets (`[x for x in …]` is a
// `for_in_clause`, not the `for_statement` this function matches) do NOT leak into the enclosing scope in
// Python 3 and are correctly never visited here. A nested `def NAME` / `class NAME` shadows NAME in its
// ENCLOSING scope for the rest of that scope (Python binds the def statement's own name where the def
// STATEMENT sits, not inside the function it defines) — attributed one byte BEFORE the nested def/class's
// own span starts, so the fact lands on the enclosing scope rather than inside the newly-declared one
// (verified empirically with `--match`, not merely reasoned about: a byte at the def/class node's own
// start resolves INSIDE that new symbol's own span, one byte earlier does not).
// Is `name` declared `global`/`nonlocal` anywhere in the function that encloses `n` — searched over that
// function's OWN body only, never crossing into a nested def/class/lambda's body (a nested scope's
// global/nonlocal statements bind there, not here)? Python's `global`/`nonlocal` statement scopes the
// WHOLE enclosing function regardless of where in the function body it textually sits, so a reassignment
// anywhere in that function to a name the function has declared global/nonlocal never creates a local
// shadow — it rewrites the OUTER binding, same as the declaration statement itself (see the SCOPE doc
// above capturePythonRebindShadowDecls). `n` with no enclosing function_definition is module scope, where
// `global`/`nonlocal` cannot appear — always false there.
inline bool pythonNameIsGlobalOrNonlocalHere( TSNode n, std::string_view name, std::string_view src )
{
    const bool nGiven = !ts_node_is_null( n );
    EXPECTS( nGiven, "n is the rebind/for/named_expression/as_pattern node the caller is currently visiting — "
                      "the tree walker never dispatches on a null node" );
    TSNode fn = ts_node_parent( n );
    while( !ts_node_is_null( fn ) && !kindIs( ts_node_type( fn ), "function_definition" ) )
    {
        fn = ts_node_parent( fn );
    }
    const bool fnIsNullOrFnDef = ts_node_is_null( fn ) || kindIs( ts_node_type( fn ), "function_definition" );
    ASSUME( fnIsNullOrFnDef, "the loop above exits only when fn is null (walked off the tree) or a function_definition" );
    if( ts_node_is_null( fn ) )
    {
        return false;   // module scope — global/nonlocal cannot appear there
    }
    const TSNode body = fieldChild( fn, NodeField::Body );
    if( ts_node_is_null( body ) )
    {
        return false;
    }
    std::vector<TSNode> stack{ body };
    while( !stack.empty() )
    {
        const TSNode cur = stack.back();
        stack.pop_back();
        const char* ct = ts_node_type( cur );
        if( kindIs( ct, "global_statement" ) || kindIs( ct, "nonlocal_statement" ) )
        {
            const std::uint32_t cc = ts_node_named_child_count( cur );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode id = ts_node_named_child( cur, i );
                if( kindIs( ts_node_type( id ), "identifier" ) && nodeTextOf( id, src ) == name )
                {
                    return true;
                }
            }
            continue;
        }
        if( kindIs( ct, "function_definition" ) || kindIs( ct, "class_definition" ) || kindIs( ct, "lambda" ) )
        {
            continue;   // nested scope — never crossed
        }
        const std::uint32_t cc = ts_node_named_child_count( cur );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            stack.push_back( ts_node_named_child( cur, i ) );
        }
    }
    return false;
}

inline void capturePythonRebindShadowDecls( TSNode n, const char* t, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawBind>& binds )
{
    std::vector<TSNode> targets;   // reused scratch, cleared before each shape below
    // `ownStart` is the fallback attribution (this statement's own position, function-local veto evidence);
    // a name this function has declared global/nonlocal gets the SAME file-wide startByte=0 treatment the
    // declaration statement itself uses below, because the reassignment rewrites the outer binding, not a
    // local one — see pythonNameIsGlobalOrNonlocalHere.
    const auto emitAll = [ & ]( TSNode site, std::uint32_t ownStart )
    {
        for( const TSNode& id : targets )
        {
            const std::uint32_t at = pythonNameIsGlobalOrNonlocalHere( site, nodeTextOf( id, src ), src ) ? 0u : ownStart;
            pushRawBind( fileId, lang, nodeTextOf( id, src ), std::string{}, BindSite{ at, 0u, 0u }, LocalBindKind::VarDecl, binds );
        }
    };

    if( kindIs( t, "assignment" ) || kindIs( t, "augmented_assignment" ) )
    {
        targets.clear();
        collectPythonNameTargets( fieldChild( n, NodeField::Left ), targets );
        emitAll( n, ts_node_start_byte( n ) );
        return;
    }
    if( kindIs( t, "for_statement" ) )
    {
        targets.clear();
        collectPythonNameTargets( fieldChild( n, NodeField::Left ), targets );
        emitAll( n, ts_node_start_byte( n ) );
        return;
    }
    if( kindIs( t, "named_expression" ) )   // walrus `(tm := …)` — the grammar allows only a bare name here
    {
        const TSNode nm = fieldChild( n, NodeField::Name );
        if( !ts_node_is_null( nm ) && kindIs( ts_node_type( nm ), "identifier" ) )
        {
            const std::uint32_t ownStart = ts_node_start_byte( n );
            const std::uint32_t at       = pythonNameIsGlobalOrNonlocalHere( n, nodeTextOf( nm, src ), src ) ? 0u : ownStart;
            pushRawBind( fileId, lang, nodeTextOf( nm, src ), std::string{}, BindSite{ at, 0u, 0u }, LocalBindKind::VarDecl, binds );
        }
        return;
    }
    if( kindIs( t, "as_pattern" ) )   // `with X as tm:` AND `except X as tm:` share this ONE grammar node
    {
        const TSNode alias  = fieldChild( n, NodeField::Alias );
        const bool   hasTgt = !ts_node_is_null( alias ) && kindIs( ts_node_type( alias ), "as_pattern_target" ) && ts_node_named_child_count( alias ) > 0;
        const TSNode target = hasTgt ? ts_node_named_child( alias, 0 ) : alias;   // grammar wraps the alias in `as_pattern_target`
        if( !ts_node_is_null( target ) && kindIs( ts_node_type( target ), "identifier" ) )
        {
            const std::uint32_t ownStart = ts_node_start_byte( n );
            const std::uint32_t at       = pythonNameIsGlobalOrNonlocalHere( n, nodeTextOf( target, src ), src ) ? 0u : ownStart;
            pushRawBind( fileId, lang, nodeTextOf( target, src ), std::string{}, BindSite{ at, 0u, 0u }, LocalBindKind::VarDecl, binds );
        }
        return;
    }
    if( kindIs( t, "delete_statement" ) )   // `del tm` (single target) / `del tm, other` (wrapped in expression_list)
    {
        targets.clear();
        const std::uint32_t cc = ts_node_named_child_count( n );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            collectPythonNameTargets( ts_node_named_child( n, i ), targets );
        }
        emitAll( n, ts_node_start_byte( n ) );
        return;
    }
    if( kindIs( t, "global_statement" ) || kindIs( t, "nonlocal_statement" ) )
    {
        const std::uint32_t cc = ts_node_named_child_count( n );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const TSNode id = ts_node_named_child( n, i );
            if( kindIs( ts_node_type( id ), "identifier" ) )
            {
                // deliberate startByte=0 — file-wide, regardless of physical nesting; see the doc above.
                pushRawBind( fileId, lang, nodeTextOf( id, src ), std::string{}, BindSite{ 0u, 0u, 0u }, LocalBindKind::VarDecl, binds );
            }
        }
        return;
    }
    if( kindIs( t, "function_definition" ) || kindIs( t, "class_definition" ) )
    {
        const TSNode nm = fieldChild( n, NodeField::Name );
        if( !ts_node_is_null( nm ) && kindIs( ts_node_type( nm ), "identifier" ) )
        {
            const std::uint32_t at = ts_node_start_byte( n );   // the def/class node's OWN start — see the doc above
            pushRawBind( fileId, lang, nodeTextOf( nm, src ), std::string{}, BindSite{ at > 0 ? at - 1 : 0, 0u, 0u }, LocalBindKind::VarDecl, binds );
        }
        return;
    }
}

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
        capturePythonRebindShadowDecls( n, t, fileId, lang, src, binds );   // issue #287 round 2: rebind veto evidence
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
        // s:Symbol) as a ParamType record for the field use-site index and Rule 2's lexical lookup — the single
        // most common typed receiver shape in this repo's own source (`s.name`), and `auto` writes nothing, as for
        // parameters.
        pushTypedBind( fileId, lang, paramDeclaratorVarName( loopDeclarator, src ), declTypeOfName( fieldChild( n, NodeField::Type ), src ),
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
// FE-B (review B4b): one type parameter a generic declares (`<Tank>`, `[T any]`, `[T]`) and the declaration it belongs to
// (its owner's bytes). A written type that spells one of these inside the owner is the parameter, never a same-named class.
struct TypeParamScope
{
    std::string_view name;
    std::uint32_t    start = 0;
    std::uint32_t    end   = 0;

    bool declares( std::string_view spelled, std::uint32_t at ) const noexcept { return name == spelled && start <= at && at < end; }
};

struct BindCtx
{
    std::uint32_t              fileId = 0;
    Lang                       lang {};
    std::string_view           src;
    std::vector<RawBind>*      binds = nullptr;
    std::vector<TypeParamScope> typeParams;   // FE-B: filled as the pre-order walk meets each parameter list

    // L3 fn-pointer buffers. Positives collect here (not straight into binds) so the end-of-walk clobber
    // sweep can ask "does this var have a fn binding in this file?" — a clobbering assignment
    // (`fn = getHandler()`) matters only then, which keeps a fn-binding-free file contributing ZERO new
    // records (the whole feature inert there).
    std::vector<RawBind>       fnPos;
    std::vector<FnBindClobber> fnUnk;
    FnBindGateState            fnGate;      // value-assignment noise-gate evidence — filled by the stream, spent at the end
    bool                       cFamilyFn = false;
};

// ── FE-B receiver-evidence capture (model.h LocalBindKind::RecvType / MemberType / MethodAlias) ──────────────────────────
// the text of an identifier in any grammar's spelling (`identifier`, `type_identifier`, `simple_identifier`); "" for a null
// node or any other kind
inline constexpr std::array<std::string_view, 3> kIdentifierKinds = { "identifier", "type_identifier", "simple_identifier" };
inline std::string_view identifierText( TSNode n, std::string_view src )
{
    const std::string_view kind = ts_node_is_null( n ) ? std::string_view{} : std::string_view( ts_node_type( n ) );
    return std::ranges::find( kIdentifierKinds, kind ) != kIdentifierKinds.end() ? nodeTextOf( n, src ) : std::string_view{};
}

// The class a written TYPE names, final segment — "" for anything that names no single class (an array, a union, a
// string annotation, a generic's argument). Unwraps the annotation wrappers each grammar puts around the type.
inline std::string_view annotatedClass( TSNode node, std::string_view src )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( node ); ++guard )
    {
        if( const std::string_view name = identifierText( node, src ); !name.empty() )
        {
            return name;
        }
        const char* t = ts_node_type( node );
        if( kindIs( t, "type" ) || kindIs( t, "type_annotation" ) || kindIs( t, "pointer_type" ) || kindIs( t, "parenthesized_type" ) )
        {
            node = ts_node_named_child_count( node ) == 1 ? ts_node_named_child( node, 0 ) : TSNode{};
        }
        else if( kindIs( t, "qualified_type" ) )                                       // Go `pkg.T`
        {
            node = fieldChild( node, NodeField::Name );
        }
        else if( kindIs( t, "attribute" ) )                                            // Python `mod.T`
        {
            node = fieldChild( node, NodeField::Attribute );
        }
        else if( kindIs( t, "nested_type_identifier" ) )                               // TS `ns.T`
        {
            node = fieldChild( node, NodeField::Name );
        }
        else if( kindIs( t, "generic_type" ) || kindIs( t, "generic_name" ) )          // TS `T<U>` / Go `T[U]` / Java / C# `T<U>`: the class
        {
            node = ts_node_named_child_count( node ) > 0 ? ts_node_named_child( node, 0 ) : TSNode{};
        }
        else if( kindIs( t, "nullable_type" ) || kindIs( t, "optional_type" ) )       // C# / Kotlin `T?`, Swift `T?`: the class
        {
            node = ts_node_named_child_count( node ) > 0 ? ts_node_named_child( node, 0 ) : TSNode{};
        }
        else if( kindIs( t, "user_type" ) || kindIs( t, "scoped_type_identifier" ) )   // Kotlin / Swift `a.B<C>`, Java `a.B`: the last
        {                                                                              // name segment, never a type argument
            TSNode last{};
            for( std::uint32_t i = 0, k = ts_node_named_child_count( node ); i < k; ++i )
            {
                const TSNode c = ts_node_named_child( node, i );
                if( kindIs( ts_node_type( c ), "type_identifier" ) )
                {
                    last = c;
                }
            }
            node = last;
        }
        else if( kindIs( t, "qualified_name" ) )                                       // C# `a.B`
        {
            node = fieldChild( node, NodeField::Name );
        }
        else
        {
            return {};   // an array, a function type, C#'s implicit `var`, a predefined/primitive type: no single class
        }
    }
    return {};
}

inline void pushEvidenceBind( BindCtx& cx, LocalBindKind kind, std::string_view var, std::string_view type, std::string_view imported,
                              std::uint32_t at, bool flag )
{
    EXPECTS( kind == LocalBindKind::RecvType || kind == LocalBindKind::MemberType || kind == LocalBindKind::MethodAlias || kind == LocalBindKind::NameAlias
                 || kind == LocalBindKind::StaticMember,
             "only the receiver-evidence kinds ride this emitter" );
    if( type.empty() || ( var.empty() && !( kind == LocalBindKind::RecvType && flag ) ) )
    {
        return;   // a nameless record is kept only for a method's own class (Go `func (T) m()`, JS `T.prototype.m = …`)
    }
    RawBind b;
    b.fileId    = cx.fileId;
    b.startByte = at;
    b.lang      = cx.lang;
    b.kind      = kind;
    b.isFromAssignment = flag;
    b.var.assign( var );
    b.typeName.assign( type );
    b.importedName.assign( imported );
    cx.binds->push_back( std::move( b ) );
}

// the class a constructor-shaped initializer names — JS/TS `new Foo( … )`, Python `Foo( … )`, Go `Foo{ … }` / `&Foo{ … }`
inline std::string_view constructedBy( TSNode value, Lang lang, std::string_view src )
{
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    if( lang == Lang::Python )
    {
        if( !kindIs( ts_node_type( value ), "call" ) )
        {
            return {};
        }
        const TSNode fn = fieldChild( value, NodeField::Function );
        return ( !ts_node_is_null( fn ) && kindIs( ts_node_type( fn ), "identifier" ) ) ? nodeTextOf( fn, src ) : std::string_view{};
    }
    if( lang == Lang::Kotlin || lang == Lang::Swift )
    {
        // `Store( … )` is spelled like a function call: a capitalized callee is read as the class it constructs (the house
        // convention of both languages). A lower-case factory (`make()`) names no class, and a capitalized name that is no
        // class in the tree proves nothing downstream (ReceiverEvidence finds no `Name::member`).
        if( !kindIs( ts_node_type( value ), "call_expression" ) || ts_node_named_child_count( value ) == 0 )
        {
            return {};
        }
        const TSNode callee = ts_node_named_child( value, 0 );
        const std::string_view name = kindIs( ts_node_type( callee ), "simple_identifier" ) ? nodeTextOf( callee, src ) : std::string_view{};
        return ( !name.empty() && name.front() >= 'A' && name.front() <= 'Z' ) ? name : std::string_view{};
    }
    return constructedClass( value, lang, src );
}


// FE-B (review B4b): the names one type parameter declares, visible over [start, end): the leading identifier(s) after any
// annotation, modifier or variance (Java/C#/Kotlin/Swift/TS `T`, Go `A, B any`), or Python 3.12's `type`-wrapped name.
inline void noteTypeParameter( BindCtx& cx, TSNode param, std::uint32_t start, std::uint32_t end )
{
    bool named = false;
    for( std::uint32_t i = 0, k = ts_node_named_child_count( param ); i < k; ++i )
    {
        TSNode c = ts_node_named_child( param, i );
        if( !named && kindIs( ts_node_type( c ), "type" ) && ts_node_named_child_count( c ) == 1 )
        {
            c = ts_node_named_child( c, 0 );   // Python `def f[T]( … )`
        }
        if( const std::string_view name = identifierText( c, cx.src ); !name.empty() )
        {
            cx.typeParams.push_back( { name, start, end } );
            named = true;
        }
        else if( named )
        {
            return;   // the bound / constraint after the names
        }
    }
}

// a parameter LIST — the generic declaration that owns it is its parent, and the parameters are visible over all of it
// (the pre-order walk meets the list before the owner's parameters, fields and body)
inline void noteTypeParameters( BindCtx& cx, TSNode list )
{
    const TSNode owner = ts_node_parent( list );
    if( ts_node_is_null( owner ) )
    {
        return;
    }
    const std::uint32_t start = ts_node_start_byte( owner );
    const std::uint32_t end   = ts_node_end_byte( owner );
    if( cx.lang == Lang::Python )
    {
        noteTypeParameter( cx, list, start, end );   // Python's `type_parameter` IS the list: `[A, B]` → one `type` per name
        return;
    }
    for( std::uint32_t i = 0, k = ts_node_named_child_count( list ); i < k; ++i )
    {
        const TSNode p = ts_node_named_child( list, i );
        if( kindIs( ts_node_type( p ), "type_parameter" ) || kindIs( ts_node_type( p ), "type_parameter_declaration" ) )
        {
            noteTypeParameter( cx, p, start, end );
        }
    }
}

// Go `func ( b Box[T] ) m()`: the receiver's type arguments are the method's type parameters
inline void noteGoReceiverTypeParameters( BindCtx& cx, TSNode method )
{
    std::vector<TSNode> pending{ fieldChild( method, NodeField::Receiver ) };
    for( int guard = 0; guard < 64 && !pending.empty(); ++guard )
    {
        const TSNode n = pending.back();
        pending.pop_back();
        if( ts_node_is_null( n ) )
        {
            continue;
        }
        if( kindIs( ts_node_type( n ), "type_arguments" ) )
        {
            for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
            {
                TSNode a = ts_node_named_child( n, i );
                if( kindIs( ts_node_type( a ), "type_elem" ) && ts_node_named_child_count( a ) == 1 )
                {
                    a = ts_node_named_child( a, 0 );
                }
                if( const std::string_view name = identifierText( a, cx.src ); !name.empty() )
                {
                    cx.typeParams.push_back( { name, ts_node_start_byte( method ), ts_node_end_byte( method ) } );
                }
            }
            continue;
        }
        for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
        {
            pending.push_back( ts_node_named_child( n, i ) );
        }
    }
}

// is `name`, written at byte `at`, a type parameter of a generic that encloses it
inline bool namesTypeParameter( const BindCtx& cx, std::string_view name, std::uint32_t at ) noexcept
{
    return std::ranges::any_of( cx.typeParams, [ & ]( const TypeParamScope& p ) { return p.declares( name, at ); } );
}

// the class a written type names at byte `at` — "" when it names none, or names a type parameter (`<Tank> … Tank t`)
inline std::string_view writtenClass( const BindCtx& cx, TSNode type, std::uint32_t at )
{
    const std::string_view cls = annotatedClass( type, cx.src );
    return ( !cls.empty() && namesTypeParameter( cx, cls, at ) ) ? std::string_view{} : cls;
}

// FE-B: Java's `var` is inference, not a class: the written type, unless it is `var`, else what the initializer constructs.
// A written type that is a type parameter names no class, and the initializer does not override it.
inline std::string_view declaredOrConstructed( const BindCtx& cx, TSNode type, TSNode value, std::uint32_t at )
{
    const std::string_view written = annotatedClass( type, cx.src );
    if( !written.empty() && !( written == "var" && cx.lang == Lang::Java ) )
    {
        return namesTypeParameter( cx, written, at ) ? std::string_view{} : written;
    }
    return constructedBy( value, cx.lang, cx.src );
}

// ── scopes (review B4a) ─────────────────────────────────────────────────────────────────────────────────────────────
// A local's record carries the bytes it is visible in (RawBind spanStart/spanEnd; {0,0} = anywhere in its definition), so
// receiverevidence.h visibleLocal can tell which binding of a name a call site sees. A binding whose class is unknown is
// still recorded (a TOMBSTONE): it hides the field or the outer local of its name over its span and proves nothing.

// the nearest proper ancestor of `n` whose kind is one of `kinds`; null when none within 64 levels
inline TSNode ancestorOfKind( TSNode n, std::initializer_list<std::string_view> kinds )
{
    TSNode p = ts_node_is_null( n ) ? TSNode{} : ts_node_parent( n );
    for( int guard = 0; guard < 64 && !ts_node_is_null( p ); ++guard )
    {
        if( std::ranges::find( kinds, std::string_view( ts_node_type( p ) ) ) != kinds.end() )
        {
            return p;
        }
        p = ts_node_parent( p );
    }
    return TSNode{};
}

// a name recorded at `at` and visible over `scope` ({0,0} when there is none: the whole definition) — the whole of it, or
// (`fromHere`, a block's declaration) from `at` to its end
inline BindSite siteOver( std::uint32_t at, TSNode scope, bool fromHere ) noexcept
{
    if( ts_node_is_null( scope ) )
    {
        return { at, 0u, 0u };
    }
    return { at, fromHere ? at : ts_node_start_byte( scope ), ts_node_end_byte( scope ) };
}
inline BindSite siteIn( std::uint32_t at, TSNode scope ) noexcept { return siteOver( at, scope, false ); }
inline BindSite siteFrom( std::uint32_t at, TSNode scope ) noexcept { return siteOver( at, scope, true ); }

// one local binding of `var`, naming class `cls` ("" = unknown), visible over `site`'s span. `flag`: Go's method receiver.
inline void pushLocalEvidence( BindCtx& cx, std::string_view var, std::string_view cls, BindSite site, bool flag = false )
{
    if( var.empty() )
    {
        return;
    }
    RawBind b;
    b.fileId    = cx.fileId;
    b.startByte = site.startByte;
    b.lang      = cx.lang;
    b.kind      = LocalBindKind::RecvType;
    b.isFromAssignment = flag;
    b.spanStart = site.spanStart;
    b.spanEnd   = site.spanEnd;
    b.var.assign( var );
    b.typeName.assign( cls );
    cx.binds->push_back( std::move( b ) );
}
// the same for a name NODE (an identifier of any grammar's spelling; anything else records nothing)
inline void pushLocalEvidence( BindCtx& cx, TSNode name, std::string_view cls, BindSite site )
{
    pushLocalEvidence( cx, identifierText( name, cx.src ), cls, site );   // "" records nothing
}
// every identifier `node` holds at any depth (a destructuring / tuple pattern's names), each as a tombstone over `site`
inline void pushPatternTombstones( BindCtx& cx, TSNode node, BindSite site )
{
    std::vector<TSNode> pending{ node };
    for( int guard = 0; guard < 256 && !pending.empty(); ++guard )
    {
        const TSNode n = pending.back();
        pending.pop_back();
        if( ts_node_is_null( n ) )
        {
            continue;
        }
        const char* t = ts_node_type( n );
        if( kindIs( t, "identifier" ) || kindIs( t, "simple_identifier" ) || kindIs( t, "shorthand_property_identifier_pattern" ) )
        {
            pushLocalEvidence( cx, nodeTextOf( n, cx.src ), {}, site );
            continue;
        }
        if( kindIs( t, "type_identifier" ) || kindIs( t, "user_type" ) || kindIs( t, "type_annotation" ) || kindIs( t, "predefined_type" ) )
        {
            continue;
        }
        for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
        {
            pending.push_back( ts_node_named_child( n, i ) );
        }
    }
}
// a field whose class is unknown (its written type is a type parameter): a tombstone, so it hides a base class's field
inline void pushMemberTombstone( BindCtx& cx, std::string_view var, std::uint32_t at )
{
    if( var.empty() )
    {
        return;
    }
    RawBind b;
    b.fileId    = cx.fileId;
    b.startByte = at;
    b.lang      = cx.lang;
    b.kind      = LocalBindKind::MemberType;
    b.var.assign( var );
    cx.binds->push_back( std::move( b ) );
}

// FE-B (review B3): one declarator's evidence — `name` declared with the class its written `type` names, else the class its
// initializer `value` constructs. A parameter or local whose class is unknown (`var s = make()`) is still a DECLARATION:
// recorded with no class (a tombstone), so it hides a same-named field (receiverevidence.h declaresLocal) and proves nothing.
// A local is visible over `site` (review B4a); a field (MemberType) belongs to its class.
inline void pushDeclaratorEvidence( BindCtx& cx, LocalBindKind kind, TSNode type, TSNode name, TSNode value, BindSite site )
{
    if( ts_node_is_null( name ) || !( kindIs( ts_node_type( name ), "identifier" ) || kindIs( ts_node_type( name ), "simple_identifier" ) ) )
    {
        return;
    }
    const std::string_view cls = declaredOrConstructed( cx, type, value, site.startByte );
    if( kind == LocalBindKind::RecvType )
    {
        pushLocalEvidence( cx, name, cls, site );
    }
    else if( !cls.empty() )
    {
        pushEvidenceBind( cx, kind, nodeTextOf( name, cx.src ), cls, {}, site.startByte, false );
    }
    else
    {
        pushMemberTombstone( cx, nodeTextOf( name, cx.src ), site.startByte );
    }
}

// the first (or, with `last`, the last) named child of `node` whose kind is one of `kinds`; null when none — Kotlin's grammar
// carries no field names and Swift's reuses `name` for the parameter, its label and its type
inline TSNode namedChildOfKind( TSNode node, std::initializer_list<std::string_view> kinds, bool last = false )
{
    TSNode hit{};
    for( std::uint32_t i = 0, k = ts_node_named_child_count( node ); i < k; ++i )
    {
        const TSNode c = ts_node_named_child( node, i );
        if( std::ranges::find( kinds, std::string_view( ts_node_type( c ) ) ) != kinds.end() )
        {
            hit = c;
            if( !last )
            {
                break;
            }
        }
    }
    return hit;
}

// FE-B (review B3, B4): Java — a typed parameter (its method's or lambda's), each declarator of a local (from the
// declaration to its block's end) or field declaration, and every other binding form: an enhanced-for variable, an
// inferred lambda parameter, a catch parameter, a try resource, and the pattern variables of `instanceof` and `case`
// (visible in their enclosing block — `if (!(o instanceof T t)) return;` keeps `t` after the `if`, so the block is the
// superset; their class is not recorded, since an `else` branch does not see them).
inline void captureJavaDeclEvidence( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    const auto callable = [ & ] { return ancestorOfKind( n, { "method_declaration", "constructor_declaration", "compact_constructor_declaration", "lambda_expression" } ); };
    const auto block    = [ & ] { return ancestorOfKind( n, { "block", "switch_block_statement_group", "switch_rule", "lambda_expression", "method_declaration" } ); };
    if( kindIs( t, "formal_parameter" ) )
    {
        pushDeclaratorEvidence( cx, LocalBindKind::RecvType, fieldChild( n, NodeField::Type ), fieldChild( n, NodeField::Name ), TSNode{}, siteIn( at, callable() ) );
        return;
    }
    if( kindIs( t, "enhanced_for_statement" ) )
    {
        const TSNode name = fieldChild( n, NodeField::Name );
        pushDeclaratorEvidence( cx, LocalBindKind::RecvType, fieldChild( n, NodeField::Type ), name, TSNode{},
                                siteIn( ts_node_is_null( name ) ? at : ts_node_start_byte( name ), n ) );
        return;
    }
    if( kindIs( t, "lambda_expression" ) )
    {
        pushLocalEvidence( cx, fieldChild( n, NodeField::Parameters ), {}, siteIn( at, n ) );   // `x -> …` (an identifier only)
        return;
    }
    if( kindIs( t, "inferred_parameters" ) )
    {
        pushPatternTombstones( cx, n, siteIn( at, ts_node_parent( n ) ) );   // `( a, b ) -> …`
        return;
    }
    if( kindIs( t, "catch_formal_parameter" ) )
    {
        pushLocalEvidence( cx, fieldChild( n, NodeField::Name ), {}, siteIn( at, ts_node_parent( n ) ) );
        return;
    }
    if( kindIs( t, "resource" ) )
    {
        pushDeclaratorEvidence( cx, LocalBindKind::RecvType, fieldChild( n, NodeField::Type ), fieldChild( n, NodeField::Name ), fieldChild( n, NodeField::Value ),
                                siteIn( at, ancestorOfKind( n, { "try_with_resources_statement" } ) ) );
        return;
    }
    if( kindIs( t, "instanceof_expression" ) )
    {
        pushLocalEvidence( cx, fieldChild( n, NodeField::Name ), {}, siteIn( at, block() ) );   // a record pattern: its components below
        return;
    }
    if( kindIs( t, "type_pattern" ) || kindIs( t, "record_pattern_component" ) )
    {
        pushLocalEvidence( cx, namedChildOfKind( n, { "identifier" }, true ), {}, siteIn( at, block() ) );
        return;
    }
    if( !kindIs( t, "local_variable_declaration" ) && !kindIs( t, "field_declaration" ) )
    {
        return;
    }
    const bool          field = kindIs( t, "field_declaration" );
    const LocalBindKind kind  = field ? LocalBindKind::MemberType : LocalBindKind::RecvType;
    const TSNode        type  = fieldChild( n, NodeField::Type );
    const BindSite      site  = field ? BindSite{ at, 0u, 0u } : siteFrom( at, ts_node_parent( n ) );
    for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
    {
        const TSNode d = ts_node_named_child( n, i );
        if( kindIs( ts_node_type( d ), "variable_declarator" ) )
        {
            pushDeclaratorEvidence( cx, kind, type, fieldChild( d, NodeField::Name ), fieldChild( d, NodeField::Value ), site );
        }
    }
}

// FE-B (review B3, B4): C# — a typed parameter (its method's, local function's or lambda's), each declarator of a local
// (from the declaration to its block's end) or field declaration, a property, and every other binding form: a foreach
// variable, an implicit lambda parameter, a catch variable, a query range variable, a deconstruction, and the variables a
// pattern or an `out var` declares (visible in their enclosing block, a superset, with no class recorded).
inline void captureCSharpDeclEvidence( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    const auto block = [ & ] { return ancestorOfKind( n, { "block", "switch_section", "switch_expression_arm", "lambda_expression", "arrow_expression_clause" } ); };
    if( kindIs( t, "parameter" ) )
    {
        const TSNode callable = ancestorOfKind( n, { "method_declaration", "constructor_declaration", "destructor_declaration", "operator_declaration",
                                                     "conversion_operator_declaration", "indexer_declaration", "local_function_statement",
                                                     "lambda_expression", "anonymous_method_expression", "accessor_declaration" } );
        pushDeclaratorEvidence( cx, LocalBindKind::RecvType, fieldChild( n, NodeField::Type ), fieldChild( n, NodeField::Name ), TSNode{}, siteIn( at, callable ) );
        return;
    }
    if( kindIs( t, "implicit_parameter" ) )
    {
        pushLocalEvidence( cx, nodeTextOf( n, cx.src ), {}, siteIn( at, ts_node_parent( n ) ) );   // `x => …`
        return;
    }
    if( kindIs( t, "foreach_statement" ) )
    {
        const TSNode left = fieldChild( n, NodeField::Left );
        if( !ts_node_is_null( left ) && kindIs( ts_node_type( left ), "identifier" ) )
        {
            pushLocalEvidence( cx, left, writtenClass( cx, fieldChild( n, NodeField::Type ), at ), siteIn( ts_node_start_byte( left ), n ) );
        }
        else
        {
            pushPatternTombstones( cx, left, siteIn( at, n ) );   // `foreach ( var ( a, b ) in … )`
        }
        return;
    }
    if( kindIs( t, "declaration_pattern" ) || kindIs( t, "declaration_expression" ) || kindIs( t, "recursive_pattern" ) || kindIs( t, "var_pattern" ) )
    {
        const TSNode name = fieldChild( n, NodeField::Name );
        pushPatternTombstones( cx, ts_node_is_null( name ) && kindIs( t, "var_pattern" ) ? n : name, siteIn( at, block() ) );
        return;
    }
    if( kindIs( t, "tuple_pattern" ) )
    {
        pushPatternTombstones( cx, n, siteIn( at, block() ) );   // `var ( a, b ) = p;`
        return;
    }
    if( kindIs( t, "catch_declaration" ) )
    {
        pushLocalEvidence( cx, fieldChild( n, NodeField::Name ), {}, siteIn( at, ts_node_parent( n ) ) );
        return;
    }
    if( kindIs( t, "from_clause" ) || kindIs( t, "join_clause" ) || kindIs( t, "let_clause" ) || kindIs( t, "query_continuation" ) || kindIs( t, "join_into_clause" ) )
    {
        pushLocalEvidence( cx, fieldChild( n, NodeField::Name ), {}, siteIn( at, ancestorOfKind( n, { "query_expression" } ) ) );
        return;
    }
    if( kindIs( t, "property_declaration" ) )
    {
        pushDeclaratorEvidence( cx, LocalBindKind::MemberType, fieldChild( n, NodeField::Type ), fieldChild( n, NodeField::Name ), fieldChild( n, NodeField::Value ),
                                BindSite{ at, 0u, 0u } );
        return;
    }
    if( !kindIs( t, "variable_declaration" ) )
    {
        return;
    }
    // a field's declaration sits in a field_declaration, a local's in a local_declaration_statement (or a using/for), whose
    // block is where it is visible
    TSNode up = ts_node_parent( n );
    const bool field = !ts_node_is_null( up ) && kindIs( ts_node_type( up ), "field_declaration" );
    if( !ts_node_is_null( up ) && kindIs( ts_node_type( up ), "local_declaration_statement" ) )
    {
        up = ts_node_parent( up );
    }
    const LocalBindKind kind = field ? LocalBindKind::MemberType : LocalBindKind::RecvType;
    const BindSite      site = field ? BindSite{ at, 0u, 0u } : siteFrom( at, up );
    const TSNode        type = fieldChild( n, NodeField::Type );
    for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
    {
        const TSNode d = ts_node_named_child( n, i );
        if( kindIs( ts_node_type( d ), "variable_declarator" ) )
        {
            // the initializer is the declarator's last named child, when it has one besides the name (no field names it)
            const TSNode name  = fieldChild( d, NodeField::Name );
            const TSNode value = ts_node_named_child_count( d ) > 1 ? ts_node_named_child( d, ts_node_named_child_count( d ) - 1 ) : TSNode{};
            pushDeclaratorEvidence( cx, kind, type, name, ts_node_eq( value, name ) ? TSNode{} : value, site );
        }
    }
}

// FE-B (review B3, B4): Kotlin — a typed parameter (its function's or lambda's; `val` constructor parameters are
// properties), a local or property declaration (a property in a class body, a local elsewhere, visible from the declaration
// to its block's end), and every other variable a declaration binds: a for variable, a lambda parameter, a destructuring
// entry, a `when ( val x = … )` subject, a catch parameter.
inline void captureKotlinDeclEvidence( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    if( kindIs( t, "parameter" ) || kindIs( t, "class_parameter" ) )
    {
        const bool property = kindIs( t, "class_parameter" );
        if( property && ts_node_is_null( namedChildOfKind( n, { "binding_pattern_kind" } ) ) )
        {
            return;   // a plain constructor parameter, not a property
        }
        const TSNode callable = ancestorOfKind( n, { "function_declaration", "anonymous_function", "secondary_constructor", "setter", "lambda_literal" } );
        pushDeclaratorEvidence( cx, property ? LocalBindKind::MemberType : LocalBindKind::RecvType, namedChildOfKind( n, { "user_type", "nullable_type" }, true ),
                                namedChildOfKind( n, { "simple_identifier" }, true ), TSNode{}, property ? BindSite{ at, 0u, 0u } : siteIn( at, callable ) );
        return;
    }
    if( kindIs( t, "catch_block" ) )
    {
        pushLocalEvidence( cx, namedChildOfKind( n, { "simple_identifier" } ), {}, siteIn( at, n ) );
        return;
    }
    if( kindIs( t, "variable_declaration" ) )
    {
        // a declaration's own variable is read with the declaration below; here, every other place a variable is bound
        TSNode up = ts_node_parent( n );
        if( !ts_node_is_null( up ) && kindIs( ts_node_type( up ), "multi_variable_declaration" ) )
        {
            up = ts_node_parent( up );
        }
        if( ts_node_is_null( up ) || kindIs( ts_node_type( up ), "property_declaration" ) )
        {
            return;
        }
        TSNode scope = up;   // a for loop
        if( kindIs( ts_node_type( up ), "lambda_parameters" ) || kindIs( ts_node_type( up ), "when_subject" ) )
        {
            scope = ts_node_parent( up );   // the lambda / the when expression
        }
        else if( !kindIs( ts_node_type( up ), "for_statement" ) )
        {
            scope = ancestorOfKind( n, { "for_statement", "lambda_literal", "when_expression", "function_declaration" } );
        }
        pushLocalEvidence( cx, namedChildOfKind( n, { "simple_identifier" } ), writtenClass( cx, namedChildOfKind( n, { "user_type", "nullable_type" } ), at ),
                           siteIn( at, scope ) );
        return;
    }
    if( !kindIs( t, "property_declaration" ) )
    {
        return;
    }
    const TSNode up    = ts_node_parent( n );
    const bool   field = !ts_node_is_null( up ) && ( kindIs( ts_node_type( up ), "class_body" ) || kindIs( ts_node_type( up ), "enum_class_body" ) );
    const BindSite site = field ? BindSite{ at, 0u, 0u } : siteFrom( at, up );
    const TSNode var = namedChildOfKind( n, { "variable_declaration" } );
    if( !ts_node_is_null( var ) )
    {
        pushDeclaratorEvidence( cx, field ? LocalBindKind::MemberType : LocalBindKind::RecvType, namedChildOfKind( var, { "user_type", "nullable_type" } ),
                                namedChildOfKind( var, { "simple_identifier" } ), namedChildOfKind( n, { "call_expression" } ), site );
        return;
    }
    const TSNode multi = namedChildOfKind( n, { "multi_variable_declaration" } );   // `val ( a, b ) = p`
    for( std::uint32_t i = 0, k = ts_node_is_null( multi ) || field ? 0u : ts_node_named_child_count( multi ); i < k; ++i )
    {
        const TSNode v = ts_node_named_child( multi, i );
        pushLocalEvidence( cx, namedChildOfKind( v, { "simple_identifier" } ), writtenClass( cx, namedChildOfKind( v, { "user_type", "nullable_type" } ), at ), site );
    }
}

// Swift: where the names a pattern (or an if/guard/while condition) binds are visible — the statement that binds them,
// the rest of the enclosing block for `guard` and for a declaration
inline BindSite swiftBindingSite( TSNode n, std::uint32_t at )
{
    const TSNode s = ancestorOfKind( n, { "for_statement", "if_statement", "while_statement", "repeat_while_statement", "switch_entry", "catch_block",
                                          "lambda_literal", "guard_statement", "property_declaration", "function_declaration", "init_declaration" } );
    if( !ts_node_is_null( s ) && ( kindIs( ts_node_type( s ), "guard_statement" ) || kindIs( ts_node_type( s ), "property_declaration" ) ) )
    {
        return { at, ts_node_start_byte( s ), ts_node_end_byte( ts_node_parent( s ) ) };
    }
    return siteIn( at, s );
}

// FE-B (review B3, B4): Swift — a typed parameter (its function's), a local or property declaration (a property in a
// class body, a local elsewhere, visible from the declaration to its block's end), a closure parameter, and every name a
// pattern binds: for-in, if/guard/while `let`, `case let`, catch, a tuple declaration.
inline void captureSwiftDeclEvidence( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    if( kindIs( t, "parameter" ) )
    {
        // `label p: T`: the LAST identifier is the parameter's own name
        const TSNode callable = ancestorOfKind( n, { "function_declaration", "init_declaration", "subscript_declaration", "lambda_literal" } );
        pushDeclaratorEvidence( cx, LocalBindKind::RecvType, namedChildOfKind( n, { "user_type", "optional_type" }, true ),
                                namedChildOfKind( n, { "simple_identifier" }, true ), TSNode{}, siteIn( at, callable ) );
        return;
    }
    if( kindIs( t, "lambda_parameter" ) )
    {
        pushLocalEvidence( cx, namedChildOfKind( n, { "simple_identifier" } ), writtenClass( cx, namedChildOfKind( n, { "user_type", "optional_type" } ), at ),
                           siteIn( at, ancestorOfKind( n, { "lambda_literal" } ) ) );
        return;
    }
    if( kindIs( t, "pattern" ) )
    {
        const TSNode up = ts_node_parent( n );
        if( !ts_node_is_null( up ) && kindIs( ts_node_type( up ), "property_declaration" ) && !ts_node_is_null( namedChildOfKind( n, { "simple_identifier" } ) ) )
        {
            return;   // a plain declaration: read with its type below
        }
        for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
        {
            const TSNode c = ts_node_named_child( n, i );
            if( kindIs( ts_node_type( c ), "simple_identifier" ) )
            {
                pushLocalEvidence( cx, c, {}, swiftBindingSite( n, at ) );
            }
        }
        return;
    }
    if( kindIs( t, "if_statement" ) || kindIs( t, "guard_statement" ) || kindIs( t, "while_statement" ) )
    {
        // `if let x = …`: the bound name is the statement's own `bound_identifier` child
        const BindSite site = kindIs( t, "guard_statement" ) ? BindSite{ at, at, ts_node_end_byte( ts_node_parent( n ) ) } : siteIn( at, n );
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char* field = ts_tree_cursor_current_field_name( &cursor.cur );
            if( field != nullptr && kindIs( field, "bound_identifier" ) )
            {
                pushLocalEvidence( cx, c, {}, site );
            }
            return true;
        } );
        return;
    }
    if( !kindIs( t, "property_declaration" ) )
    {
        return;
    }
    const TSNode   up      = ts_node_parent( n );
    const bool     field   = !ts_node_is_null( up ) && ( kindIs( ts_node_type( up ), "class_body" ) || kindIs( ts_node_type( up ), "enum_class_body" ) );
    const TSNode   pattern = fieldChild( n, NodeField::Name );
    const TSNode   ann     = namedChildOfKind( n, { "type_annotation" } );
    pushDeclaratorEvidence( cx, field ? LocalBindKind::MemberType : LocalBindKind::RecvType, ts_node_is_null( ann ) ? TSNode{} : namedChildOfKind( ann, { "user_type", "optional_type" } ),
                            ts_node_is_null( pattern ) ? TSNode{} : namedChildOfKind( pattern, { "simple_identifier" } ), fieldChild( n, NodeField::Value ),
                            field ? BindSite{ at, 0u, 0u } : siteFrom( at, up ) );
}

// FE-B (review B3): a declaration's evidence in Java, C#, Kotlin and Swift — a typed parameter, a typed or constructed
// local (RecvType), a typed or constructed field / property (MemberType); (review B4) every other binding form, and the
// type parameters a generic declares. The base resolver bound these receivers by name alone; FE-B proves a member call
// only through evidence, so the declarations are read here.
inline void captureTypedDeclEvidence( BindCtx& cx, TSNode n, const char* t )
{
    const std::uint32_t at = ts_node_start_byte( n );
    if( kindIs( t, "type_parameters" ) || kindIs( t, "type_parameter_list" ) )
    {
        noteTypeParameters( cx, n );
        return;
    }
    if( cx.lang == Lang::Java )
    {
        captureJavaDeclEvidence( cx, n, t, at );
    }
    else if( cx.lang == Lang::CSharp )
    {
        captureCSharpDeclEvidence( cx, n, t, at );
    }
    else if( cx.lang == Lang::Kotlin )
    {
        captureKotlinDeclEvidence( cx, n, t, at );
    }
    else
    {
        captureSwiftDeclEvidence( cx, n, t, at );
    }
}

// JS/TS (review B4a): where a declarator's names are visible — a `let`/`const` from the declaration to the end of its block
// (or loop / switch / function), a `var` anywhere in its function ({0,0})
inline BindSite jsDeclaratorSite( TSNode declarator )
{
    const std::uint32_t at   = ts_node_start_byte( declarator );
    const TSNode        decl = ts_node_parent( declarator );
    if( ts_node_is_null( decl ) || !kindIs( ts_node_type( decl ), "lexical_declaration" ) )
    {
        return { at, 0u, 0u };
    }
    TSNode scope = ts_node_parent( decl );
    for( int guard = 0; guard < 64 && !ts_node_is_null( scope ); ++guard )
    {
        const char* st = ts_node_type( scope );
        if( jsFunctionScope( scope ) || kindIs( st, "program" ) || kindIs( st, "statement_block" ) || kindIs( st, "for_statement" )
            || kindIs( st, "for_in_statement" ) || kindIs( st, "switch_body" ) || kindIs( st, "class_static_block" ) )
        {
            return siteFrom( at, scope );
        }
        scope = ts_node_parent( scope );
    }
    return { at, 0u, 0u };
}

// each name a JS/TS binding pattern binds (never an initializer's or a type's), as a tombstone over `site`
inline void pushJsPatternTombstones( BindCtx& cx, TSNode pattern, BindSite site )
{
    for( const std::string& name : jsPatternNames( pattern, cx.src ) )
    {
        pushLocalEvidence( cx, name, {}, site );
    }
}

// FE-B (review B4a): Python binds a name for the whole function wherever it assigns it (no block scope), so every
// rebinding form records the name with no span: a `for` target, a `with … as` / `except … as` / `case … as` name, a
// `match` capture, a walrus name, and an assignment the base Type record does not already type (an annotation is read below, a constructor call by
// the base pass). A lambda's parameters and a comprehension's targets are visible inside it only; an untyped parameter
// hides an enclosing function's binding of its name.
inline void capturePythonBindingTombstones( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    std::vector<TSNode> targets;
    const auto tombstones = [ & ]( TSNode target, BindSite site )
    {
        targets.clear();
        collectPythonNameTargets( target, targets );
        for( const TSNode& id : targets )
        {
            pushLocalEvidence( cx, id, {}, site );
        }
    };
    if( kindIs( t, "for_statement" ) )
    {
        tombstones( fieldChild( n, NodeField::Left ), BindSite{ at, 0u, 0u } );
    }
    else if( kindIs( t, "for_in_clause" ) )
    {
        tombstones( fieldChild( n, NodeField::Left ), siteIn( at, ts_node_parent( n ) ) );
    }
    else if( kindIs( t, "named_expression" ) )
    {
        tombstones( fieldChild( n, NodeField::Name ), BindSite{ at, 0u, 0u } );
    }
    else if( kindIs( t, "as_pattern" ) )
    {
        // `with X as n:` / `except X as n:` (an `alias` field), `case P() as n:` (the last identifier)
        TSNode alias = fieldChild( n, NodeField::Alias );
        if( ts_node_is_null( alias ) )
        {
            alias = namedChildOfKind( n, { "identifier" }, true );
        }
        tombstones( !ts_node_is_null( alias ) && kindIs( ts_node_type( alias ), "as_pattern_target" ) && ts_node_named_child_count( alias ) > 0
                        ? ts_node_named_child( alias, 0 ) : alias, BindSite{ at, 0u, 0u } );
    }
    else if( kindIs( t, "case_pattern" ) || kindIs( t, "keyword_pattern" ) || kindIs( t, "splat_pattern" ) )
    {
        // a `match` capture: a bare name (`case n:`, `[n, *rest]`, `P(x=n)`); a dotted name is a value pattern, a class
        // pattern's class sits under class_pattern
        for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
        {
            const TSNode c = ts_node_named_child( n, i );
            const char*  ct = ts_node_type( c );
            if( kindIs( ct, "dotted_name" ) && ts_node_named_child_count( c ) == 1 )
            {
                pushLocalEvidence( cx, ts_node_named_child( c, 0 ), {}, BindSite{ at, 0u, 0u } );
            }
            else if( kindIs( t, "splat_pattern" ) && kindIs( ct, "identifier" ) )
            {
                pushLocalEvidence( cx, c, {}, BindSite{ at, 0u, 0u } );
            }
        }
    }
    else if( kindIs( t, "lambda" ) )
    {
        const TSNode params = fieldChild( n, NodeField::Parameters );
        for( std::uint32_t i = 0, k = ts_node_is_null( params ) ? 0u : ts_node_named_child_count( params ); i < k; ++i )
        {
            const TSNode p = ts_node_named_child( params, i );
            pushLocalEvidence( cx, kindIs( ts_node_type( p ), "identifier" ) ? p : fieldChild( p, NodeField::Name ), {}, siteIn( at, n ) );
        }
    }
    else if( kindIs( t, "parameters" ) )
    {
        // an untyped parameter (a typed one is read with its annotation): `x`, `x=1`, `*xs`, `**kw`
        for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
        {
            const TSNode p  = ts_node_named_child( n, i );
            const char*  pt = ts_node_type( p );
            const TSNode id = kindIs( pt, "identifier" ) ? p
                            : kindIs( pt, "default_parameter" ) ? fieldChild( p, NodeField::Name )
                            : ( kindIs( pt, "list_splat_pattern" ) || kindIs( pt, "dictionary_splat_pattern" ) ) && ts_node_named_child_count( p ) > 0
                                ? ts_node_named_child( p, 0 ) : TSNode{};
            pushLocalEvidence( cx, id, {}, BindSite{ ts_node_start_byte( p ), 0u, 0u } );
        }
    }
    else if( kindIs( t, "assignment" ) && ts_node_is_null( fieldChild( n, NodeField::Type ) ) )
    {
        const TSNode lhs = fieldChild( n, NodeField::Left );
        const TSNode rhs = fieldChild( n, NodeField::Right );
        const bool   typedByBase = !ts_node_is_null( lhs ) && kindIs( ts_node_type( lhs ), "identifier" ) && !ts_node_is_null( rhs )
                                && kindIs( ts_node_type( rhs ), "call" ) && !ts_node_is_null( fieldChild( rhs, NodeField::Function ) )
                                && kindIs( ts_node_type( fieldChild( rhs, NodeField::Function ) ), "identifier" );
        if( !typedByBase )
        {
            tombstones( lhs, BindSite{ at, 0u, 0u } );
        }
    }
}

// FE-B (review B4a): Go — where a name declared inside a function is visible: a short variable declaration in a block from
// there to the block's end; in an if / for / switch header, that whole statement
inline BindSite goShortVarSite( TSNode decl, std::uint32_t at )
{
    const TSNode up = ts_node_parent( decl );
    if( ts_node_is_null( up ) )
    {
        return { at, 0u, 0u };
    }
    const char* ut = ts_node_type( up );
    if( kindIs( ut, "block" ) )
    {
        return siteFrom( at, up );
    }
    if( kindIs( ut, "for_clause" ) )
    {
        return siteIn( at, ts_node_parent( up ) );
    }
    if( kindIs( ut, "if_statement" ) || kindIs( ut, "expression_switch_statement" ) || kindIs( ut, "type_switch_statement" ) )
    {
        return siteIn( at, up );
    }
    return siteFrom( at, ancestorOfKind( decl, { "block" } ) );
}

// each identifier an expression_list holds (Go's left-hand sides), recorded naming `cls` over `site`
inline void pushGoNames( BindCtx& cx, TSNode list, std::string_view cls, BindSite site )
{
    for( std::uint32_t i = 0, k = ts_node_is_null( list ) ? 0u : ts_node_named_child_count( list ); i < k; ++i )
    {
        pushLocalEvidence( cx, ts_node_named_child( list, i ), cls, site );   // `_` is an identifier too: harmless, never a receiver
    }
}

// FE-B: Go's receiver evidence — typed parameters (the method receiver names the method's class), typed / constructed
// locals, struct field types; (review B4) every other name a function binds (a range / type-switch / receive variable, an
// untyped short declaration, a reassignment), and the type parameters a generic declares.
inline void captureGoEvidence( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    const std::string_view src = cx.src;
    if( kindIs( t, "type_parameter_list" ) )
    {
        noteTypeParameters( cx, n );
    }
    else if( kindIs( t, "method_declaration" ) )
    {
        noteGoReceiverTypeParameters( cx, n );
    }
    else if( kindIs( t, "parameter_declaration" ) )
    {
        const TSNode list     = ts_node_parent( n );
        const TSNode method   = ts_node_is_null( list ) ? TSNode{} : ts_node_parent( list );
        const bool   receiver = !ts_node_is_null( method ) && kindIs( ts_node_type( method ), "method_declaration" )
                             && ts_node_eq( fieldChild( method, NodeField::Receiver ), list );
        const std::string_view type = writtenClass( cx, fieldChild( n, NodeField::Type ), at );
        const BindSite         site = siteIn( at, ancestorOfKind( n, { "function_declaration", "method_declaration", "func_literal" } ) );
        bool named = false;
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char* field = ts_tree_cursor_current_field_name( &cursor.cur );
            if( field != nullptr && kindIs( field, "name" ) && kindIs( ts_node_type( c ), "identifier" ) )
            {
                named = true;
                pushLocalEvidence( cx, nodeTextOf( c, src ), type, site, receiver );
            }
            return true;
        } );
        if( !named && receiver )
        {
            pushEvidenceBind( cx, LocalBindKind::RecvType, {}, type, {}, at, true );   // `func (T) m()`: the class alone
        }
    }
    else if( kindIs( t, "var_spec" ) )
    {
        std::string_view type = writtenClass( cx, fieldChild( n, NodeField::Type ), at );
        const TSNode values = fieldChild( n, NodeField::Value );
        if( type.empty() && ts_node_is_null( fieldChild( n, NodeField::Type ) ) && !ts_node_is_null( values ) && ts_node_named_child_count( values ) == 1 )
        {
            type = constructedBy( ts_node_named_child( values, 0 ), cx.lang, src );
        }
        const BindSite site = siteFrom( at, ancestorOfKind( n, { "block" } ) );
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char* field = ts_tree_cursor_current_field_name( &cursor.cur );
            if( field != nullptr && kindIs( field, "name" ) && kindIs( ts_node_type( c ), "identifier" ) )
            {
                pushLocalEvidence( cx, nodeTextOf( c, src ), type, site );
            }
            return true;
        } );
    }
    else if( kindIs( t, "short_var_declaration" ) )
    {
        // `x := T{}` names T; `a, b := …`, `x := f()` name no class. (A plain assignment `x = …` keeps x's declared type:
        // Go's static typing, so it records nothing.)
        const TSNode left  = fieldChild( n, NodeField::Left );
        const TSNode right = fieldChild( n, NodeField::Right );
        const bool   one   = !ts_node_is_null( left ) && !ts_node_is_null( right ) && ts_node_named_child_count( left ) == 1 && ts_node_named_child_count( right ) == 1;
        pushGoNames( cx, left, one ? constructedBy( ts_node_named_child( right, 0 ), cx.lang, src ) : std::string_view{}, goShortVarSite( n, at ) );
    }
    else if( ( kindIs( t, "range_clause" ) || kindIs( t, "receive_statement" ) ) && jsHasToken( n, ":=" ) )
    {
        // `for k, v := range xs` (the loop) / `case v := <-ch:` (the case); with `=` they assign names declared elsewhere
        pushGoNames( cx, fieldChild( n, NodeField::Left ), {}, siteIn( at, ancestorOfKind( n, { "for_statement", "communication_case" } ) ) );
    }
    else if( kindIs( t, "type_switch_statement" ) )
    {
        pushGoNames( cx, fieldChild( n, NodeField::Alias ), {}, siteIn( at, n ) );   // `switch v := x.(type)`
    }
    else if( kindIs( t, "field_declaration" ) )
    {
        const std::string_view written = annotatedClass( fieldChild( n, NodeField::Type ), src );
        const bool             param   = !written.empty() && namesTypeParameter( cx, written, at );
        const std::string_view type    = param ? std::string_view{} : written;
        bool named = false;
        ChildCursor cursor( n );
        forEachChild( n, cursor.cur, [ & ]( TSNode c )
        {
            const char* field = ts_tree_cursor_current_field_name( &cursor.cur );
            if( field != nullptr && kindIs( field, "name" ) && kindIs( ts_node_type( c ), "field_identifier" ) )
            {
                named = true;
                if( param )
                {
                    pushMemberTombstone( cx, nodeTextOf( c, src ), at );   // `item T` in `Box[T any]`
                }
                else
                {
                    pushEvidenceBind( cx, LocalBindKind::MemberType, nodeTextOf( c, src ), type, {}, at, false );
                }
            }
            return true;
        } );
        if( !named && !param )
        {
            pushEvidenceBind( cx, LocalBindKind::MemberType, type, type, {}, at, true );   // an embedded field: its methods are promoted
        }
    }
}

// FE-B: JS/TS receiver evidence — constructed / typed locals and parameters, `this.x` and TS field types, `static` members,
// prototype methods; (review B4) every other name a function binds (an untyped parameter, a destructuring, a for-in/of
// variable, a catch parameter, a reassignment), each visible where the language scopes it, and TS type parameters.
inline void captureJsEvidence( BindCtx& cx, TSNode n, const char* t, std::uint32_t at )
{
    const Lang             lang = cx.lang;
    const std::string_view src  = cx.src;
    if( kindIs( t, "type_parameters" ) )
    {
        noteTypeParameters( cx, n );
    }
    else if( kindIs( t, "variable_declarator" ) )
    {
        const TSNode   name = fieldChild( n, NodeField::Name );
        const BindSite site = jsDeclaratorSite( n );
        if( ts_node_is_null( name ) || !kindIs( ts_node_type( name ), "identifier" ) )
        {
            pushJsPatternTombstones( cx, name, site );   // `const { a, b } = o`, `const [ a ] = xs`
            return;
        }
        const TSNode value = fieldChild( n, NodeField::Value );
        if( lang == Lang::JavaScript )
        {
            pushLocalEvidence( cx, name, constructedBy( value, lang, src ), site );
            return;
        }
        // TS records a written or constructed class as a Type record already (the base pass: the annotation's first
        // type_identifier, else ctorTypeOf); here, a declaration that names none hides an outer binding of its name, and one
        // whose written type is a type parameter ties that Type record (unknown)
        const TSNode ann = fieldChild( n, NodeField::Type );
        TSNode       written{};
        if( !ts_node_is_null( ann ) )
        {
            ChildCursor annCursor( ann );
            forEachChild( ann, annCursor.cur, [ & ]( TSNode c )
            {
                if( !kindIs( ts_node_type( c ), "type_identifier" ) )
                {
                    return true;
                }
                written = c;
                return false;
            } );
        }
        if( !ts_node_is_null( written ) )
        {
            if( namesTypeParameter( cx, nodeTextOf( written, src ), at ) )
            {
                pushLocalEvidence( cx, name, {}, BindSite{ at, 0u, 0u } );
            }
        }
        else if( ctorTypeOf( value, src ).empty() )
        {
            pushLocalEvidence( cx, name, {}, site );
        }
    }
    else if( kindIs( t, "formal_parameters" ) )
    {
        const BindSite site = siteIn( at, ts_node_parent( n ) );   // the function, arrow or method the list belongs to
        for( std::uint32_t i = 0, k = ts_node_named_child_count( n ); i < k; ++i )
        {
            const TSNode p       = ts_node_named_child( n, i );
            const TSNode pattern = lang == Lang::TypeScript ? fieldChild( p, NodeField::Pattern ) : TSNode{};
            if( !ts_node_is_null( pattern ) && kindIs( ts_node_type( pattern ), "identifier" ) )
            {
                pushLocalEvidence( cx, pattern, writtenClass( cx, fieldChild( p, NodeField::Type ), at ), site );
            }
            else
            {
                pushJsPatternTombstones( cx, p, site );
            }
        }
    }
    else if( kindIs( t, "arrow_function" ) )
    {
        pushLocalEvidence( cx, fieldChild( n, NodeField::Parameter ), {}, siteIn( at, n ) );   // `x => …` (an identifier only)
    }
    else if( kindIs( t, "for_in_statement" ) )
    {
        const bool lexical = jsHasToken( n, "let" ) || jsHasToken( n, "const" );
        pushJsPatternTombstones( cx, fieldChild( n, NodeField::Left ), lexical ? siteIn( at, n ) : BindSite{ at, 0u, 0u } );
    }
    else if( kindIs( t, "catch_clause" ) )
    {
        pushJsPatternTombstones( cx, fieldChild( n, NodeField::Parameter ), siteIn( at, n ) );
    }
    else if( kindIs( t, "method_definition" ) )
    {
        // `static m () {}`: the member's side of the lookup, recorded inside its body so it attributes to the member
        const TSNode name = fieldChild( n, NodeField::Name );
        const TSNode body = fieldChild( n, NodeField::Body );
        bool         isStatic = false;
        for( std::uint32_t i = 0, k = ts_node_child_count( n ); i < k && !isStatic; ++i )
        {
            isStatic = kindIs( ts_node_type( ts_node_child( n, i ) ), "static" );
        }
        if( isStatic && !ts_node_is_null( name ) && !ts_node_is_null( body ) )
        {
            pushEvidenceBind( cx, LocalBindKind::StaticMember, nodeTextOf( name, src ), "static", {}, ts_node_start_byte( body ), false );
        }
    }
    else if( lang == Lang::TypeScript && kindIs( t, "public_field_definition" ) )
    {
        const TSNode name = fieldChild( n, NodeField::Name );
        if( !ts_node_is_null( name ) && kindIs( ts_node_type( name ), "property_identifier" ) )
        {
            const std::string_view written = annotatedClass( fieldChild( n, NodeField::Type ), src );
            if( !written.empty() && namesTypeParameter( cx, written, at ) )
            {
                pushMemberTombstone( cx, nodeTextOf( name, src ), at );   // `item: T` in `class Box<T>`
                return;
            }
            const std::string_view type = written.empty() ? constructedBy( fieldChild( n, NodeField::Value ), lang, src ) : written;
            pushEvidenceBind( cx, LocalBindKind::MemberType, nodeTextOf( name, src ), type, {}, at, false );
        }
    }
    else if( kindIs( t, "assignment_expression" ) )
    {
        const TSNode lhs = fieldChild( n, NodeField::Left );
        if( ts_node_is_null( lhs ) )
        {
            return;
        }
        if( kindIs( ts_node_type( lhs ), "identifier" ) )
        {
            if( lang == Lang::JavaScript )   // a JS rebinding can change the class (no span); a TS one keeps the declared type
            {
                pushLocalEvidence( cx, lhs, constructedBy( fieldChild( n, NodeField::Right ), lang, src ), BindSite{ at, 0u, 0u } );
            }
            return;
        }
        if( !kindIs( ts_node_type( lhs ), "member_expression" ) )
        {
            return;
        }
        const TSNode obj  = fieldChild( lhs, NodeField::Object );
        const TSNode prop = fieldChild( lhs, NodeField::Property );
        if( !ts_node_is_null( obj ) && !ts_node_is_null( prop ) && kindIs( ts_node_type( obj ), "this" ) && kindIs( ts_node_type( prop ), "property_identifier" ) )
        {
            pushEvidenceBind( cx, LocalBindKind::MemberType, nodeTextOf( prop, src ), constructedBy( fieldChild( n, NodeField::Right ), lang, src ), {}, at, false );
        }
        // `Foo.prototype.m = function …`: the member's class, recorded INSIDE the function so the record attributes to it
        const TSNode rhs = fieldChild( n, NodeField::Right );
        if( !ts_node_is_null( obj ) && kindIs( ts_node_type( obj ), "member_expression" ) && !ts_node_is_null( rhs )
            && ( kindIs( ts_node_type( rhs ), "function_expression" ) || kindIs( ts_node_type( rhs ), "function" ) || kindIs( ts_node_type( rhs ), "arrow_function" ) )
            && nodeTextOf( fieldChild( obj, NodeField::Property ), src ) == "prototype" )
        {
            const TSNode ctor = fieldChild( obj, NodeField::Object );
            if( !ts_node_is_null( ctor ) && kindIs( ts_node_type( ctor ), "identifier" ) )
            {
                pushEvidenceBind( cx, LocalBindKind::RecvType, {}, nodeTextOf( ctor, src ), {}, ts_node_start_byte( rhs ), true );
            }
        }
    }
}

// FE-B: one node's receiver evidence: Python, JS/TS and Go, and (review B3) Java, C#, Kotlin and Swift declarations.
inline void captureReceiverEvidence( BindCtx& cx, TSNode n, const char* t )
{
    const Lang             lang = cx.lang;
    const std::string_view src  = cx.src;
    const std::uint32_t    at   = ts_node_start_byte( n );
    if( lang == Lang::Python )
    {
        if( kindIs( t, "typed_parameter" ) || kindIs( t, "typed_default_parameter" ) )
        {
            TSNode name = fieldChild( n, NodeField::Name );
            if( ts_node_is_null( name ) && ts_node_named_child_count( n ) > 0 )
            {
                name = ts_node_named_child( n, 0 );   // typed_parameter spells its identifier without a field
            }
            if( !ts_node_is_null( name ) && kindIs( ts_node_type( name ), "identifier" ) )
            {
                pushLocalEvidence( cx, name, writtenClass( cx, fieldChild( n, NodeField::Type ), at ), BindSite{ at, 0u, 0u } );
            }
        }
        else if( kindIs( t, "type_parameter" ) )
        {
            noteTypeParameters( cx, n );   // `def f[T]( … )` / `class C[T]:`
        }
        else if( kindIs( t, "import_from_statement" ) )
        {
            ChildCursor cursor( n );
            forEachChild( n, cursor.cur, [ & ]( TSNode c )
            {
                if( kindIs( ts_node_type( c ), "aliased_import" ) )
                {
                    const TSNode name  = fieldChild( c, NodeField::Name );
                    const TSNode alias = fieldChild( c, NodeField::Alias );
                    if( !ts_node_is_null( name ) && !ts_node_is_null( alias ) )
                    {
                        pushEvidenceBind( cx, LocalBindKind::NameAlias, nodeTextOf( alias, src ), finalSegment( nodeTextOf( name, src ) ), {}, ts_node_start_byte( c ), false );
                    }
                }
                return true;
            } );
        }
        else if( kindIs( t, "assignment" ) )
        {
            const TSNode lhs = fieldChild( n, NodeField::Left );
            const TSNode rhs = fieldChild( n, NodeField::Right );
            if( ts_node_is_null( lhs ) )
            {
                return;
            }
            const char* lt = ts_node_type( lhs );
            if( kindIs( lt, "identifier" ) && !ts_node_is_null( fieldChild( n, NodeField::Type ) ) )
            {
                pushLocalEvidence( cx, lhs, writtenClass( cx, fieldChild( n, NodeField::Type ), at ), BindSite{ at, 0u, 0u } );
            }
            else if( kindIs( lt, "identifier" ) && !ts_node_is_null( rhs ) && kindIs( ts_node_type( rhs ), "attribute" ) )
            {
                const TSNode obj  = fieldChild( rhs, NodeField::Object );
                const TSNode attr = fieldChild( rhs, NodeField::Attribute );
                if( !ts_node_is_null( obj ) && !ts_node_is_null( attr ) && kindIs( ts_node_type( obj ), "identifier" ) )
                {
                    pushEvidenceBind( cx, LocalBindKind::MethodAlias, nodeTextOf( lhs, src ), nodeTextOf( obj, src ), nodeTextOf( attr, src ), at, false );
                }
            }
            else if( kindIs( lt, "attribute" ) )
            {
                const TSNode obj  = fieldChild( lhs, NodeField::Object );
                const TSNode attr = fieldChild( lhs, NodeField::Attribute );
                if( !ts_node_is_null( obj ) && !ts_node_is_null( attr ) && kindIs( ts_node_type( obj ), "identifier" ) && nodeTextOf( obj, src ) == "self" )
                {
                    pushEvidenceBind( cx, LocalBindKind::MemberType, nodeTextOf( attr, src ), constructedBy( rhs, lang, src ), {}, at, false );
                }
            }
        }
        capturePythonBindingTombstones( cx, n, t, at );
        return;
    }
    if( lang == Lang::JavaScript || lang == Lang::TypeScript )
    {
        captureJsEvidence( cx, n, t, at );
    }
    else if( lang == Lang::Java || lang == Lang::CSharp || lang == Lang::Kotlin || lang == Lang::Swift )
    {
        captureTypedDeclEvidence( cx, n, t );
    }
    else if( lang == Lang::Go )
    {
        captureGoEvidence( cx, n, t, at );
    }
}

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
        const DeclType written = declTypeOfName( fieldChild( n, NodeField::Type ), src );
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
                emitDeclBinds( fileId, lang, declarator, src, declaredTypeOf( written, fieldChild( c, NodeField::Value ), src ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, declarator ), scope.end }, binds );
            }
            else   // plain declarator (identifier / pointer_declarator / reference_declarator), no initializer
            {
                emitDeclBinds( fileId, lang, c, src, written,
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, c ), scope.end }, binds );
            }
            return true;
        } );
    }
    // C++ `x = Foo();` (re-assignment to a constructor) — assignment_expression inside an expression_statement. The
    // record carries the constructor's qualified text like a declaration's does (`x = std::map<K, V>()`, kParserVer 98),
    // and is marked an assignment's: its callee may be a function (`x = makeFoo()`), kParserVer 104.
    else if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && kindIs( t, "assignment_expression" ) )
    {
        const TSNode lhs = fieldChild( n, NodeField::Left );
        const TSNode rhs = fieldChild( n, NodeField::Right );
        if( !ts_node_is_null( lhs ) && kindIs( ts_node_type( lhs ), "identifier" ) )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                pushTypedBind( fileId, lang, src.substr( a, b - a ), assignedTypeOf( rhs, src ), BindSite{ ts_node_start_byte( n ), 0u, 0u },
                               LocalBindKind::Type, binds );
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
    // Java declarations are resolver veto evidence for `Identifier::method`. Tree-sitter cannot
    // distinguish a type receiver from a value receiver, so a parameter/local/field with the same
    // spelling must prevent the class-name proof — but only where that binding is in scope.
    else if( lang == Lang::Java )
    {
        captureJavaShadowDecls( n, t, fileId, lang, src, binds );
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
    captureReceiverEvidence( cx, n, t );   // FE-B: typed parameters/locals, field types, method aliases (Python, JS/TS, Go, Java, C#, Kotlin, Swift)

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
