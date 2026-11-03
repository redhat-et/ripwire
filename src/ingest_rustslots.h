#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_rustslots.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp"
#endif

// ingest_rustslots.h — FN-SLOT part 2 (Rust): the language-specific STORE and CALL records of the slot join, read by the one
// language-blind join (valuerefindex.h SlotIndex). Rust's row in model.h kVrSlotLangs is callSide ParenFieldCall, typeKey
// ModuleType. This walk records ONLY what that join reads — it is not the general value-reference capture of the C, JS, Python
// and Go families (ingest_valuerefs.h): no parameter call, container, return or local value is recorded for Rust.
//
// RECORDS (the shapes model.h RefRole::Value / Through document; ingest_valuerefs.h RECORD SHAPE):
//   * a function PATH as an argument of a call whose callee is a path (`CallEval::new( 1, eval_block )`, `reg( Editor::backspace )`,
//     `f::<D>` with its turbofish dropped): Value, scope 'a', recvVar = the callee as written with `Self` resolved to the impl
//     type ("CallEval::new"), argCount = the argument's position (a `self` parameter is position 0 of a path call), name = the
//     function's last segment, memberRoot = its owner TYPE when the path names one (`Editor` in `Editor::backspace`; a module
//     path `eval::eval_block` names no owner), memberVia = the module path written before the owner or the function
//     (`crate::other`, `std::thread`, "" bare: valuerefindex.h slot_join::RustPaths decides where it can reach; recvVar keeps
//     the callee's own). A method call's arguments (`cx.listener( Self::f )`) are a floor: no row.
//   * a function path stored into a struct FIELD — a struct expression `T { f: path }` / `T { path }` (shorthand), the value
//     unwrapped from `Box::new( … )` / `Rc::new( … )` / `Arc::new( … )`, or an assignment `self.f = path` / `x.f = path`:
//     Value, scope 'x', memberPath = the field, memberCtor = the struct type as written, its module path kept (`Self` → the
//     impl type; `x.f`: "" — x's type is not read, the name tier), memberVia = the value's module path.
//   * a PARAMETER stored the same way (`fn new( eval: EvalFn ) -> Self { Self { eval } }`): the slot fact of a registrar
//     (model.h kValueRefSlotParamScope), recvVar = the function's name, argCount = the parameter's position.
//   * a call through a field `(self.eval)( … )` (Rust calls a function-valued field only so: `x.f( … )` is always a method
//     call): Through, scope kValueRefSlotCallScope, name = the root, memberPath = the last field, memberCtor = the impl type
//     when the root is `self` and the chain is one field, else "" (the name tier).
// SHADOWING: an identifier bound anywhere in the enclosing function — a parameter, a `let`, closure, `for`, `match` or
// `if let` pattern — is never a function value (the whole function is one scope here: a conservative floor), and a BARE CALLEE it
// binds (`fn run( spawn: fn( fn() ) ) { spawn( worker ) }`) is never the in-tree registrar of that name: the argument row still
// prints (the function is used as a value), but names no registrar (recvVar cleared). An identifier
// that starts upper-case is a constant, a unit struct or a variant (`map( Some )`), never a function: no row.
// FLOORS: closures and method-call arguments are no rows, nor `let g = f`, an array element or a returned function (Rust
// value references are path-call arguments and field stores only: --safe-delete / --dead-code may miss the rest); a function
// of an inline `mod m { … }` is a module member (`t="method" sc="m"`), so a value or registrar there resolves to nothing
// (valuerefindex.h isClassMember); a macro body is opaque; nodes deeper than kVrMaxDepth are not
// visited — disclosed by the file's depth-cut record, as the general walk does.

namespace rw
{

namespace
{

class RustSlotWalk
{
public:
    RustSlotWalk( Lang lang, std::uint32_t fileId, std::string_view src, std::vector<RawRef>& out ) noexcept
        : m_lang( lang ), m_fileId( fileId ), m_src( src ), m_out( out )
    {
    }
    // ONE cursor walk of the file (no cursor per node, no second walk of a function body): a function's rows that name a bare
    // identifier wait in its Fn until the function ends, when every name its patterns bind is known (finishFn).
    void run( TSNode root )
    {
        const TSLanguage* tl = ts_node_language( root );
        for( std::size_t k = 0; k < kKinds.size(); ++k )
        {
            m_sym[k] = ts_language_symbol_for_name( tl, kKinds[k].data(), static_cast<std::uint32_t>( kKinds[k].size() ), true );
        }
        const std::size_t first = m_out.size();
        ChildCursor       walker( root );   // RAII: the walk's one cursor, released on every exit (hazardpatterncheck E)
        TSTreeCursor&     cur   = walker.cur;
        std::uint32_t     depth = 0;
        for( ;; )
        {
            const TSNode n       = ts_tree_cursor_current_node( &cur );
            const bool   descend = depth + 1 < kVrMaxDepth;
            if( enter( n ) && descend && ts_tree_cursor_goto_first_child( &cur ) )
            {
                ++depth;
                continue;
            }
            if( !descend && ts_node_child_count( n ) > 0 && !opaque( n ) )
            {
                noteVrDepthCut( m_depthCut, n );
            }
            leave( n );
            bool done = false;
            while( !ts_tree_cursor_goto_next_sibling( &cur ) )
            {
                if( depth == 0 || !ts_tree_cursor_goto_parent( &cur ) )
                {
                    done = true;
                    break;
                }
                --depth;
                leave( ts_tree_cursor_current_node( &cur ) );
            }
            if( done )
            {
                break;
            }
        }
        while( !m_fns.empty() )
        {
            finishFn();   // a cut walk never left them
        }
        std::stable_sort( m_out.begin() + static_cast<std::ptrdiff_t>( first ), m_out.end(),
                          []( const RawRef& a, const RawRef& b ) { return a.startByte < b.startByte; } );   // source order, as the other walks emit
        if( m_depthCut.subtrees > 0 )
        {
            m_out.push_back( vrDepthCutRecord( m_fileId, m_lang, m_depthCut ) );
        }
    }

private:
    enum Kind : std::uint8_t { Impl, FnItem, Call, StructExpr, Assign, Let, For, MatchArm, LetCond, ClosureParams,
                               Macro, Use, Attr, InnerAttr, LineComment, BlockComment, Str, RawStr, TypeArgs, TypeParams, Where, KindCount };
    static constexpr std::array<std::string_view, KindCount> kKinds = { "impl_item", "function_item", "call_expression", "struct_expression",
                                                                       "assignment_expression", "let_declaration", "for_expression",
                                                                       "match_arm", "let_condition", "closure_parameters",
                                                                       "macro_invocation", "use_declaration", "attribute_item", "inner_attribute_item",
                                                                       "line_comment", "block_comment", "string_literal", "raw_string_literal",
                                                                       "type_arguments", "type_parameters", "where_clause" };
    // A subtree no record can come from: a macro's token trees (opaque: a floor), a `use`, an attribute, a comment, a string, a
    // type's arguments or bounds. The walk does not enter it (no depth cut either: nothing below it is ever read).
    bool opaque( TSNode n ) const noexcept
    {
        const TSSymbol sy = ts_node_symbol( n );
        for( std::size_t k = Macro; k < KindCount; ++k )
        {
            if( sy == m_sym[k] )
            {
                return true;
            }
        }
        return false;
    }
    // A row that names a bare identifier, decided when its function ends: a name the function binds is no function value — a
    // store of a parameter bound once becomes the registrar's fact (paramFact), anything else bound is dropped.
    struct Pending
    {
        RawRef           r;
        std::string_view id;
        bool             store = false;
        std::string_view callee;   // a bare callee identifier ("" for a path callee or a store): bound in the function ⇒ not a registrar
    };
    struct Fn
    {
        TSNode                        node {};
        std::string_view              name;
        std::vector<std::string_view> params;   // in position order; a `self` parameter is "self"
        std::vector<std::string_view> bound;    // every identifier a pattern of the function binds (params included)
        std::vector<Pending>          pending;
    };

    bool kind( TSNode n, Kind k ) const noexcept { return ts_node_symbol( n ) == m_sym[k]; }
    // The node's records; false: do not enter its children (an anonymous token has none worth a visit, opaque()).
    bool enter( TSNode n )
    {
        if( !ts_node_is_named( n ) || opaque( n ) )
        {
            return false;
        }
        if( kind( n, Impl ) )
        {
            m_impl.push_back( typeName( field( n, "type" ) ) );
        }
        else if( kind( n, FnItem ) )
        {
            m_fns.push_back( fnScope( n ) );
        }
        else if( kind( n, Call ) )
        {
            callAt( n );
        }
        else if( kind( n, StructExpr ) )
        {
            structAt( n );
        }
        else if( kind( n, Assign ) )
        {
            assignAt( n );
        }
        else if( !m_fns.empty() && ( kind( n, Let ) || kind( n, For ) || kind( n, MatchArm ) || kind( n, LetCond ) ) )
        {
            bindIn( field( n, "pattern" ), m_fns.back().bound, 0 );
        }
        else if( !m_fns.empty() && kind( n, ClosureParams ) )
        {
            bindIn( n, m_fns.back().bound, 0 );
        }
        return true;
    }
    void leave( TSNode n )
    {
        if( kind( n, Impl ) && m_impl.size() > 1 )
        {
            m_impl.pop_back();
        }
        else if( kind( n, FnItem ) && !m_fns.empty() && ts_node_eq( m_fns.back().node, n ) )
        {
            finishFn();
        }
    }
    void finishFn()
    {
        Fn f = std::move( m_fns.back() );
        m_fns.pop_back();
        for( Pending& p : f.pending )
        {
            if( !p.callee.empty() && std::ranges::count( f.bound, p.callee ) > 0 )
            {
                p.r.recvVar.clear();   // a parameter or a local called, never the in-tree function of that name (CR 4408459928)
            }
            const auto bound = std::ranges::count( f.bound, p.id );
            if( bound == 0 )
            {
                m_out.push_back( std::move( p.r ) );
                continue;
            }
            const auto at = std::ranges::find( f.params, p.id );
            if( !p.store || bound != 1 || at == f.params.end() || f.name.empty() )
            {
                continue;   // a local, or a parameter rebound somewhere in the function: never a function value
            }
            RawRef& r       = p.r;   // a parameter stored into a field slot: the registrar's fact, never a row
            r.name.clear();
            r.memberRoot.clear();
            r.fieldName.clear();
            r.composeRel.clear();
            r.qualifier     = std::string( 1, kValueRefSlotParamScope );
            r.recvVar       = std::string( f.name );
            r.argCount      = static_cast<std::uint16_t>( std::min<std::ptrdiff_t>( at - f.params.begin(), 0xFFFF ) );
            r.argCountKnown = true;
            m_out.push_back( std::move( r ) );
        }
    }
    // A row naming `id` (a bare identifier, "" for a path): to its function's pending list, else (outside a function) out.
    void land( RawRef&& r, std::string_view id, bool store, std::string_view callee = {} )
    {
        if( ( !id.empty() || !callee.empty() ) && !m_fns.empty() )
        {
            m_fns.back().pending.push_back( Pending{ std::move( r ), id, store, callee } );
            return;
        }
        m_out.push_back( std::move( r ) );
    }

    std::string_view text( TSNode n ) const noexcept { return nodeTextOf( n, m_src ); }   // "" for a null node
    static TSNode field( TSNode n, std::string_view name ) noexcept
    {
        return ts_node_child_by_field_name( n, name.data(), static_cast<std::uint32_t>( name.size() ) );
    }
    static bool is( TSNode n, std::string_view kind ) noexcept { return !ts_node_is_null( n ) && kind == ts_node_type( n ); }

    // The type NAME a type node spells: `T`, `T<A>` → T, `m::T` → T. "" for every other type.
    std::string_view typeName( TSNode t ) const noexcept
    {
        if( is( t, "generic_type" ) )
        {
            t = field( t, "type" );
        }
        if( is( t, "scoped_type_identifier" ) )
        {
            t = field( t, "name" );
        }
        return is( t, "type_identifier" ) ? text( t ) : std::string_view();
    }
    std::string_view implType() const noexcept { return m_impl.back(); }   // m_impl starts with "": outside every impl

    // The function's name and its parameters in position order (their names are bound; the body's patterns bind more as the
    // walk reaches them).
    Fn fnScope( TSNode fn ) const
    {
        Fn           f;
        f.node             = fn;
        f.name             = text( field( fn, "name" ) );
        const TSNode ps    = field( fn, "parameters" );
        if( !ts_node_is_null( ps ) )
        {
            ChildCursor c( ps );
            forEachNamedChild( ps, c.cur, [ & ]( TSNode p )
            {
                if( is( p, "self_parameter" ) )
                {
                    f.params.push_back( "self" );
                }
                else if( is( p, "parameter" ) )
                {
                    const TSNode pat = field( p, "pattern" );
                    f.params.push_back( is( pat, "identifier" ) ? text( pat ) : std::string_view() );   // a destructuring parameter keeps its position, names none
                    bindIn( pat, f.bound, 0 );
                }
                return true;
            } );
        }
        return f;
    }
    // Every identifier of pattern subtree `n` (the names it binds; a path or literal in it names none — over-collecting only hides).
    void bindIn( TSNode n, std::vector<std::string_view>& out, std::uint32_t depth ) const
    {
        if( ts_node_is_null( n ) || depth >= kVrMaxDepth )
        {
            return;
        }
        if( is( n, "identifier" ) )
        {
            out.push_back( text( n ) );
            return;
        }
        ChildCursor c( n );
        forEachNamedChild( n, c.cur, [ & ]( TSNode ch ) { bindIn( ch, out, depth + 1 ); return true; } );
    }

    // `Box::new` / `Rc::new` / `Arc::new` (any module path before the type): a wrapper that hands its one argument on (the value, not a registrar).
    bool wrapperCallee( TSNode fn ) const noexcept
    {
        if( !is( fn, "scoped_identifier" ) || text( field( fn, "name" ) ) != "new" )
        {
            return false;
        }
        const std::string_view path = scopeLastSegment( text( field( fn, "path" ) ) );   // `std::sync::Arc` as `Arc`
        return path == "Box" || path == "Rc" || path == "Arc";
    }
    // A value as written, through `( v )`, `Box::new( v )`, `Rc::new( v )`, `Arc::new( v )`.
    TSNode unwrap( TSNode v ) const noexcept
    {
        for( int hop = 0; hop < 4 && !ts_node_is_null( v ); ++hop )
        {
            if( is( v, "parenthesized_expression" ) )
            {
                v = ts_node_named_child( v, 0 );
                continue;
            }
            if( !is( v, "call_expression" ) )
            {
                break;
            }
            const TSNode args = field( v, "arguments" );
            if( !wrapperCallee( field( v, "function" ) ) || ts_node_named_child_count( args ) != 1 )
            {
                break;
            }
            v = ts_node_named_child( args, 0 );
        }
        return v;
    }

    // What a value node names: a function path (name, owner type), a bare identifier (decided at its function's end), or nothing.
    struct Named
    {
        std::string_view name;
        std::string      owner;
        std::string_view module;         // the module path written before the owner type or the function (`crate::a`, `std::thread`)
        bool             bare = false;   // a bare identifier: a function, a parameter or a local, as its function binds it
    };
    static bool upperLead( std::string_view s ) noexcept { return !s.empty() && s[0] >= 'A' && s[0] <= 'Z'; }
    Named named( TSNode v ) const
    {
        Named out;
        v = unwrap( v );
        if( is( v, "generic_function" ) )
        {
            v = field( v, "function" );   // `f::<D>`: the turbofish picks an instance of f
        }
        if( is( v, "identifier" ) )
        {
            const std::string_view id = text( v );
            if( !upperLead( id ) )
            {
                out.name = id;
                out.bare = true;   // its function's patterns decide it (finishFn)
            }
            return out;
        }
        if( is( v, "scoped_identifier" ) )
        {
            const TSNode           nm   = field( v, "name" );
            const TSNode           path = field( v, "path" );
            const std::string_view leaf = text( nm );
            if( !is( nm, "identifier" ) || upperLead( leaf ) )
            {
                return out;   // a variant or an associated constant
            }
            std::string_view owner = is( path, "scoped_identifier" ) ? text( field( path, "name" ) )
                                   : is( path, "generic_type" )      ? typeName( path )
                                                                     : text( path );
            if( owner == "Self" )
            {
                owner = implType();
                if( owner.empty() )
                {
                    return out;   // `Self::f` outside an impl (a trait's default body): the type is not one
                }
            }
            out.name  = leaf;
            out.owner = upperLead( owner ) ? std::string( owner ) : std::string();   // a module path names no owner type
            if( out.owner.empty() )
            {
                out.module = text( path );   // `crate::other::target`: the whole path before the function
            }
            else if( owner == text( field( path, "name" ) ) && is( path, "scoped_identifier" ) )
            {
                out.module = text( field( path, "path" ) );   // `a::Editor::f`: the module path before the owner type
            }
        }
        return out;
    }

    // `callee( … )` with a path callee: each function-path argument is an argument row; `(x.f)( … )` is a call through field f.
    void callAt( TSNode call )
    {
        const TSNode fn = field( call, "function" );
        if( is( fn, "parenthesized_expression" ) )
        {
            slotCallAt( call, ts_node_named_child( fn, 0 ) );
            return;
        }
        const TSNode callee = is( fn, "generic_function" ) ? field( fn, "function" ) : fn;
        if( wrapperCallee( callee ) )
        {
            return;   // `Box::new( f )`: the value lands where the wrapper does (unwrap), not in the wrapper
        }
        std::string      written;   // the callee as written (`Self` resolved): recvVar
        std::string      shown;     // without its module path: the row's into=
        std::string_view bareCallee;   // the callee when it is one bare identifier: a function's own binding of it shadows the registrar
        if( is( callee, "identifier" ) )
        {
            written    = std::string( text( callee ) );
            shown      = written;
            bareCallee = text( callee );
        }
        else if( is( callee, "scoped_identifier" ) )
        {
            const Named n = named( callee );
            if( n.name.empty() )
            {
                return;
            }
            shown   = n.owner.empty() ? std::string( n.name ) : n.owner + "::" + std::string( n.name );
            written = n.module.empty() ? shown : std::string( n.module ) + "::" + shown;   // resolveCallee reads the module path
        }
        else
        {
            return;   // a method call `x.m( … )`, a call result called: a floor
        }
        const TSNode args = field( call, "arguments" );
        if( ts_node_is_null( args ) )
        {
            return;
        }
        std::uint32_t pos = 0;
        ChildCursor   c( args );
        forEachNamedChild( args, c.cur, [ & ]( TSNode a )
        {
            if( is( a, "line_comment" ) || is( a, "block_comment" ) || is( a, "attribute_item" ) )
            {
                return true;
            }
            const Named n = named( a );
            if( !n.name.empty() )
            {
                RawRef r        = rawRefAt( a, m_fileId, m_lang, RefRole::Value, std::string( n.name ) );
                r.memberRoot    = n.owner;
                r.memberVia     = std::string( n.module );
                r.qualifier     = "a0";
                r.recvVar       = written;
                r.fieldName     = shown + "#arg" + std::to_string( pos );
                r.composeRel    = "#" + std::to_string( pos );
                r.argCount      = static_cast<std::uint16_t>( std::min<std::uint32_t>( pos, 0xFFFFu ) );
                r.argCountKnown = true;
                land( std::move( r ), n.bare ? n.name : std::string_view(), false, bareCallee );
            }
            ++pos;
            return true;
        } );
    }

    // `(root.a.f)( … )`: one slot call row (typed only for `self.f` inside an impl).
    void slotCallAt( TSNode call, TSNode f )
    {
        if( !is( f, "field_expression" ) )
        {
            return;
        }
        const TSNode fld = field( f, "field" );
        TSNode       root = field( f, "value" );
        int          hops = 1;
        while( is( root, "field_expression" ) )
        {
            root = field( root, "value" );
            ++hops;
        }
        if( !is( fld, "field_identifier" ) || !( is( root, "identifier" ) || is( root, "self" ) ) )
        {
            return;   // a tuple field `(x.0)( … )`, a call result's field: a floor
        }
        RawRef r     = rawRefAt( call, m_fileId, m_lang, RefRole::Through, std::string() );
        r.qualifier  = std::string( 1, kValueRefSlotCallScope );
        r.name       = std::string( text( root ) );
        r.fieldName  = std::string( text( f ) );
        r.composeRel = "." + std::string( text( fld ) );
        r.memberPath = std::string( text( fld ) );
        r.memberCtor = hops == 1 && is( root, "self" ) ? std::string( implType() ) : std::string();
        m_out.push_back( std::move( r ) );
    }

    // `T { f: v, g }`: each field value that names a function (a row) or a parameter (a registrar's fact).
    void structAt( TSNode se )
    {
        const TSNode body = field( se, "body" );
        if( ts_node_is_null( body ) )
        {
            return;
        }
        const std::string ty = structType( field( se, "name" ) );
        if( ty.empty() )
        {
            return;
        }
        ChildCursor c( body );
        forEachNamedChild( body, c.cur, [ & ]( TSNode fi )
        {
            if( is( fi, "field_initializer" ) )
            {
                const TSNode fname = field( fi, "field" );
                if( is( fname, "field_identifier" ) )
                {
                    storeAt( fi, field( fi, "value" ), text( fname ), ty );
                }
            }
            else if( is( fi, "shorthand_field_initializer" ) )
            {
                const TSNode id = ts_node_named_child( fi, 0 );
                if( is( id, "identifier" ) )
                {
                    storeAt( fi, id, text( id ), ty );
                }
            }
            return true;
        } );
    }
    // The struct type a struct expression's name spells, its path kept as written (slot_join::RustTypeKeys reads the module
    // path: `crate::a::Cfg` is a.rs's Cfg, `extcrate::Hook` no in-tree one, `E::V` a variant); `Self` → the impl type.
    std::string structType( TSNode nm ) const
    {
        if( is( nm, "generic_type_with_turbofish" ) )
        {
            nm = field( nm, "type" );
        }
        if( is( nm, "type_identifier" ) )
        {
            const std::string_view t = text( nm );
            return t == "Self" ? std::string( implType() ) : std::string( t );
        }
        if( is( nm, "scoped_type_identifier" ) )
        {
            return std::string( text( nm ) );
        }
        return {};
    }
    // A struct type as a row shows it (into=): its module path dropped (`crate::a::Cfg` → Cfg), a variant `E::V` whole.
    static std::string shownType( std::string_view ty )
    {
        const std::size_t at = ty.rfind( "::" );
        return at == std::string_view::npos || upperLead( scopeLastSegment( ty.substr( 0, at ) ) ) ? std::string( ty ) : std::string( ty.substr( at + 2 ) );
    }
    // `x.f = v`: a store into field f (typed for `self.f` inside an impl, else the name tier).
    void assignAt( TSNode as )
    {
        const TSNode lhs = field( as, "left" );
        if( !is( lhs, "field_expression" ) )
        {
            return;
        }
        const TSNode fld  = field( lhs, "field" );
        const TSNode root = field( lhs, "value" );
        if( !is( fld, "field_identifier" ) )
        {
            return;
        }
        storeAt( as, field( as, "right" ), text( fld ), is( root, "self" ) ? std::string( implType() ) : std::string() );
    }
    void storeAt( TSNode at, TSNode value, std::string_view fieldName, const std::string& ty )
    {
        const Named n = named( value );
        RawRef      r = rawRefAt( at, m_fileId, m_lang, RefRole::Value, std::string() );
        r.memberPath  = std::string( fieldName );
        r.memberCtor  = ty;
        if( n.name.empty() )
        {
            return;
        }
        r.name       = std::string( n.name );
        r.memberRoot = n.owner;
        r.memberVia  = std::string( n.module );
        r.qualifier  = "x0";
        r.fieldName  = shownType( ty ) + "." + std::string( fieldName );
        r.composeRel = "." + std::string( fieldName );
        land( std::move( r ), n.bare ? n.name : std::string_view(), true );
    }

    Lang                          m_lang;
    std::uint32_t                 m_fileId;
    std::string_view              m_src;
    std::vector<RawRef>&          m_out;
    std::vector<std::string_view> m_impl { std::string_view() };   // "" then the enclosing impl blocks' type names (`Self`)
    std::vector<Fn>               m_fns;    // the enclosing functions
    std::array<TSSymbol, KindCount> m_sym {};   // kKinds' grammar symbols
    VrDepthCut                    m_depthCut;
};

// The Rust row of model.h kVrSlotLangs: this file's slot records (RECORDS above), appended to `refs`.
inline void captureRustSlotRefs( Lang lang, std::uint32_t fileId, std::string_view src, TSNode root, std::vector<RawRef>& refs )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: Rust slot records" );
    RustSlotWalk( lang, fileId, src, refs ).run( root );
}

}   // namespace

}   // namespace rw
