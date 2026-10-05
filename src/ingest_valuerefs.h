#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_valuerefs.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp"
#endif

// ingest_valuerefs.h — REFERENCE-AS-VALUE capture: a function NAMED in a value position (a struct-field or
// dict/object/array initialiser, a call argument, an assignment's right-hand side, a parameter default, a
// return, a comparison, a JSX attribute, a decorator) rather than called. Before this pass such an identifier
// was no reference of any kind, so --callers/--callees/--impact/--uses answered a silent zero and --dead-code
// listed a function a dispatch table held (test/recallshapecheck.sh, the RED run on 40c83e4f).
//
// MECHANISM — ported from codebase-memory-mcp (MIT, Copyright (c) 2025 DeusData; THIRD_PARTY.md):
// internal/cbm/extract_usages.c handle_usages / try_emit_usage / is_direct_argument_value / is_value_field.
// There, every identifier that is not the exact callee, not a binding or write occurrence, not inside an
// import and not an argument LABEL emits a USAGE at its enclosing scope, resolved later by name; a direct
// argument value is a CALL_REFERENCE. This port keeps that shape and differs on purpose in three ways:
//   * it emits only in VALUE positions (a closed per-grammar list below), not for every identifier, so the
//     rows say WHERE the value lands (`into=`) — the binding site an agent follows;
//   * it records CALLS THROUGH A VALUE (a called parameter, `tbl[k](…)`, `tbl.k(…)` on a container that
//     received a function value) as RefRole::Through, so a reader can be told who MAY call through the slot;
//   * scope is tracked lexically (parameters, locals, for/comprehension/range/catch variables, destructuring),
//     so a same-named local hides the function, exactly as the language would.
// Both roles stay OUT of the call graph (buildGraph admits Call and Macro only): PageRank, the default map,
// count=/reaches= are unchanged. graph.h valueRefIndex resolves and joins them for the verbs.
//
// RECORD SHAPE (role-specific reuse of Reference's string fields, documented at model.h RefRole):
//   Value:   name=the referenced identifier; fieldName=into (the slot as written); recvVar=the simple
//            container identifier ("" when nested/anonymous); composeRel=the normalised key (".k", "[k]", "{}",
//            "#i"/"#kw" for an argument or a parameter default, "" for a plain assignment); qualifier=two
//            chars: scope ('f' file-scope container, 'l' local container, 'a' argument of a bare callee,
//            'p' parameter default, 'x' no container) + '1' when a FILE-SCOPE non-function declaration of the
//            same name exists in this file (graph.h then keeps the row only if this file also defines a function
//            of that name) else '0'.
//   Through: name=the container/parameter called through; fieldName=the written callee (through=);
//            composeRel=the key (".k", "[k]", "*" computed, "" bare); qualifier="p" (a parameter: argCount is its
//            index), "l" (a local container) or "f" (a file-scope container).
// A local/file Through survives only when the same scope fed that container a function value (the filter at
// scope exit / file end), so an ordinary `x.m()` adds nothing; a parameter Through always survives — its
// values arrive from callers elsewhere.
//
// FLOORS (stated in the legend and pinned by recallshapecheck): a member or qualified value (obj.f, self.f,
// ns::f, &Cls::m) and a function as the OBJECT of a member access (f.bind, f.name) are not rows; an import
// alias is a local binding; a macro body is opaque; classes are not functions; Python attribute calls never
// count as a call through a dict; nodes deeper than kVrMaxDepth are not visited.

namespace rw
{

namespace
{

using VrFam = ValueRefFamily;   // model.h: the one armed-language table the resolver indexes too

inline constexpr std::uint32_t kVrMaxDepth   = 512;   // the value-uses pass's own depth guard (ingest_sidecap.h kSideDepthUses)
inline constexpr std::size_t   kVrTextCap    = 96;    // a written slot / callee longer than this is cut with "…"

// A written slot or callee, made attribute-safe: whitespace runs collapse to one space (an XML attribute may not
// carry a raw newline) and the text is capped. Escaping is the emitter's job. The cut is serialize.h
// truncateUtf8WithEllipsis's (that header is not reachable from the ingest side): "…" only when text was really cut —
// a text of exactly kVrTextCap bytes is whole — and never inside a UTF-8 sequence (a lead byte without its
// continuation bytes would reach into=/through= as an invalid character).
inline std::string vrClean( std::string_view s )
{
    std::string out;
    out.reserve( std::min( s.size(), kVrTextCap + 4 ) );
    bool space = false;
    for( char c : s )
    {
        const bool ws = c == ' ' || c == '\n' || c == '\r' || c == '\t';
        if( ws )
        {
            space = !out.empty();
            continue;
        }
        if( space )
        {
            out.push_back( ' ' );
            space = false;
        }
        out.push_back( c );
        if( out.size() > kVrTextCap )
        {
            std::size_t cut = kVrTextCap;   // back off to the start of the sequence the cap falls inside
            while( cut > 0 && ( static_cast<unsigned char>( out[cut] ) & 0xC0u ) == 0x80u )
            {
                --cut;
            }
            out.resize( cut );
            out += "\xE2\x80\xA6";   // …
            break;
        }
    }
    ENSURES( out.size() <= kVrTextCap + 3, "a cleaned text is at most the cap plus the 3-byte ellipsis" );
    return out;
}

// A `fed` list (VrScope::fed, m_fileFed) as a sorted set: the Through filters then binary-search it.
inline void vrSortUnique( std::vector<std::string>& v )
{
    std::ranges::sort( v );
    v.erase( std::ranges::unique( v ).begin(), v.end() );
}

// The content of a string literal as written: prefix letters (b, f, r, u) and the quote pair stripped.
inline std::string_view vrStringContent( std::string_view s ) noexcept
{
    std::size_t i = 0;
    while( i < s.size() && ( ( s[i] >= 'a' && s[i] <= 'z' ) || ( s[i] >= 'A' && s[i] <= 'Z' ) ) )
    {
        ++i;
    }
    s.remove_prefix( i );
    if( s.size() >= 2 && ( s.front() == '"' || s.front() == '\'' || s.front() == '`' ) && s.back() == s.front() )
    {
        return s.substr( 1, s.size() - 2 );
    }
    return {};
}

// A key / index literal's kind, for the normalised match key: a string (its content), a number (as written), or
// anything else (a computed key).
enum class VrKeyKind : std::uint8_t { Other, String, Number };
inline VrKeyKind vrKeyKind( const char* t ) noexcept
{
    if( kindIs( t, "string" ) || kindIs( t, "string_literal" ) || kindIs( t, "interpreted_string_literal" )
        || kindIs( t, "raw_string_literal" ) || kindIs( t, "template_string" ) )
    {
        return VrKeyKind::String;
    }
    if( kindIs( t, "number" ) || kindIs( t, "number_literal" ) || kindIs( t, "integer" ) || kindIs( t, "int_literal" ) )
    {
        return VrKeyKind::Number;
    }
    return VrKeyKind::Other;
}

struct VrScope
{
    TSNode                        node {};
    bool                          isFunction = false;
    bool                          isClass    = false;   // a class body: its names are attributes, never visible inside its methods
    std::vector<std::string_view> decls;           // every name this scope declares (parameters included)
    std::vector<std::string_view> params;          // positional parameter names, in order ("" when unnamed)
    std::string_view              fnName;          // the function's own name, when it has one
    std::vector<std::string>      fed;             // containers declared here that received a function value
    std::vector<RawRef>           pending;         // calls through a container declared here, awaiting `fed`
};

struct VrAnc
{
    TSNode        node {};
    const char*   kind = "";
    TSFieldId     field = 0;          // the field this node occupies in its parent (0 = none)
    std::uint32_t namedIndex = 0;     // index among the parent's named, non-extra children
    std::uint32_t childNamed = 0;     // running count of this node's named, non-extra children entered so far
    bool          opensScope = false;
};

class ValueRefWalk
{
public:
    ValueRefWalk( VrFam fam, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<RawRef>& out )
        : m_fam( fam ), m_lang( lang ), m_fileId( fileId ), m_src( src ), m_out( out )
    {
    }

    void run( TSNode root )
    {
        const TSLanguage* tl = ts_node_language( root );
        m_fValue       = fieldIdFor( tl, NodeField::Value );
        m_fKey         = fieldIdFor( tl, NodeField::Key );
        m_fLeft        = fieldIdFor( tl, NodeField::Left );
        m_fRight       = fieldIdFor( tl, NodeField::Right );
        m_fFunction    = fieldIdFor( tl, NodeField::Function );
        m_fName        = fieldIdFor( tl, NodeField::Name );
        m_fDeclarator  = fieldIdFor( tl, NodeField::Declarator );
        m_fConsequence = fieldIdFor( tl, NodeField::Consequence );
        m_fAlternative = fieldIdFor( tl, NodeField::Alternative );
        m_fParameters  = fieldIdFor( tl, NodeField::Parameters );
        m_fParameter   = fieldIdFor( tl, NodeField::Parameter );
        m_fObject      = fieldIdFor( tl, NodeField::Object );
        m_fProperty    = fieldIdFor( tl, NodeField::Property );
        m_fField       = fieldIdFor( tl, NodeField::Field );
        m_fArgument    = fieldIdFor( tl, NodeField::Argument );
        m_fOperand     = fieldIdFor( tl, NodeField::Operand );
        m_fAttribute   = fieldIdFor( tl, NodeField::Attribute );
        m_fOperator    = fieldIdFor( tl, NodeField::Operator );
        m_fPattern     = fieldIdFor( tl, NodeField::Pattern );
        m_fDefinition  = fieldIdFor( tl, NodeField::Definition );
        m_fConstructor = fieldIdFor( tl, NodeField::Constructor );
        m_fType        = fieldIdFor( tl, NodeField::Type );
        m_fIndex       = ts_language_field_id_for_name( tl, "index", 5 );
        m_fSubscript   = ts_language_field_id_for_name( tl, "subscript", 9 );
        m_fDesignator  = ts_language_field_id_for_name( tl, "designator", 10 );
        m_fAlias       = ts_language_field_id_for_name( tl, "alias", 5 );

        VrScope file;
        file.node = root;
        m_scopes.push_back( std::move( file ) );

        ChildCursor  walker( root );   // RAII: the walk's one cursor, released on every exit (hazardpatterncheck E)
        TSTreeCursor& cur = walker.cur;
        enter( root, 0 );
        for( ;; )
        {
            if( m_anc.size() < kVrMaxDepth && ts_tree_cursor_goto_first_child( &cur ) )
            {
                enter( ts_tree_cursor_current_node( &cur ), ts_tree_cursor_current_field_id( &cur ) );
                continue;
            }
            bool done = false;
            for( ;; )
            {
                leave();
                if( m_anc.empty() )
                {
                    done = true;
                    break;
                }
                if( ts_tree_cursor_goto_next_sibling( &cur ) )
                {
                    enter( ts_tree_cursor_current_node( &cur ), ts_tree_cursor_current_field_id( &cur ) );
                    break;
                }
                ts_tree_cursor_goto_parent( &cur );
            }
            if( done )
            {
                break;
            }
        }

        // File-scope calls through a container survive only when this file fed that container a function value. A
        // container fed N times is listed N times: sorted and deduplicated once, each pending call is a binary search
        // (membership only — m_out keeps m_filePending's order).
        vrSortUnique( m_fileFed );
        for( RawRef& t : m_filePending )
        {
            if( std::ranges::binary_search( m_fileFed, t.name ) )
            {
                m_out.push_back( std::move( t ) );
            }
        }
    }

private:
    // ── node-kind tables ───────────────────────────────────────────────────────────────────────────────
    // What a node opens: a function scope (owns parameters and locals), a block scope (a Python comprehension), a
    // class body (not this walk's scope: its names are attributes), or nothing.
    enum class ScopeKind : std::uint8_t { None, Function, Block, Class };
    ScopeKind scopeKindOf( const char* t ) const noexcept
    {
        if( kindIs( t, "class_definition" ) || kindIs( t, "class_declaration" ) || kindIs( t, "class" )
            || kindIs( t, "class_specifier" ) || kindIs( t, "struct_specifier" ) )
        {
            return ScopeKind::Class;
        }
        switch( m_fam )
        {
            case VrFam::C:
                return kindIs( t, "function_definition" ) || kindIs( t, "lambda_expression" ) ? ScopeKind::Function : ScopeKind::None;
            case VrFam::Js:
                return kindIs( t, "function_declaration" ) || kindIs( t, "function_expression" ) || kindIs( t, "function" )
                    || kindIs( t, "arrow_function" ) || kindIs( t, "method_definition" )
                    || kindIs( t, "generator_function_declaration" ) || kindIs( t, "generator_function" ) ? ScopeKind::Function : ScopeKind::None;
            case VrFam::Py:
                if( kindIs( t, "function_definition" ) || kindIs( t, "lambda" ) )
                {
                    return ScopeKind::Function;
                }
                return kindIs( t, "list_comprehension" ) || kindIs( t, "set_comprehension" ) || kindIs( t, "dictionary_comprehension" )
                    || kindIs( t, "generator_expression" ) ? ScopeKind::Block : ScopeKind::None;
            case VrFam::Go:
                return kindIs( t, "function_declaration" ) || kindIs( t, "method_declaration" ) || kindIs( t, "func_literal" ) ? ScopeKind::Function : ScopeKind::None;
            case VrFam::None: break;
        }
        return ScopeKind::None;
    }
    bool isIdentifierKind( const char* t ) const noexcept
    {
        return kindIs( t, "identifier" ) || ( m_fam == VrFam::Js && kindIs( t, "shorthand_property_identifier" ) );
    }
    bool isCallKind( const char* t ) const noexcept
    {
        // Go parses `tbl[k](x)` with an identifier index as a CONVERSION to a generic type (type_conversion_expression
        // over generic_type): the grammar cannot tell a map lookup from a type instantiation, so it is read here as both.
        return m_fam == VrFam::Py ? kindIs( t, "call" )
                                  : kindIs( t, "call_expression" ) || ( m_fam == VrFam::Go && kindIs( t, "type_conversion_expression" ) );
    }

    std::string_view text( TSNode n ) const noexcept
    {
        return ts_node_is_null( n ) ? std::string_view() : nodeTextOf( n, m_src );
    }
    TSNode child( TSNode n, TSFieldId f ) const noexcept
    {
        return f == 0 ? TSNode{} : ts_node_child_by_field_id( n, f );
    }

    // ── declarations ───────────────────────────────────────────────────────────────────────────────────
    // C declarator → its declared identifier (through pointer/array/function/parenthesized/init declarators).
    std::string_view declaratorName( TSNode d, int depth = 0 ) const noexcept
    {
        if( ts_node_is_null( d ) || depth > 32 )
        {
            return {};
        }
        const char* t = ts_node_type( d );
        if( kindIs( t, "identifier" ) || kindIs( t, "field_identifier" ) )
        {
            return text( d );
        }
        const TSNode inner = child( d, m_fDeclarator );   // pointer/array/function/init declarators; else the wrapper's first child
        return declaratorName( ts_node_is_null( inner ) ? ts_node_named_child( d, 0 ) : inner, depth + 1 );
    }

    // A prototype (`int helper( int );`, `int *make( void );`) declares a FUNCTION, not an object: it hides nothing.
    // A function POINTER wraps its name in parentheses first (`int (*fp)( int )`) and is an object — the walk stops at
    // the parenthesized declarator and answers false.
    bool declaresFunction( TSNode d, int depth = 0 ) const noexcept
    {
        if( ts_node_is_null( d ) || depth > 16 )
        {
            return false;
        }
        const char* t = ts_node_type( d );
        if( kindIs( t, "function_declarator" ) )
        {
            const char* inner = ts_node_type( child( d, m_fDeclarator ) );
            return kindIs( inner, "identifier" ) || kindIs( inner, "field_identifier" ) || kindIs( inner, "qualified_identifier" );
        }
        if( kindIs( t, "pointer_declarator" ) || kindIs( t, "reference_declarator" ) )
        {
            return declaresFunction( child( d, m_fDeclarator ), depth + 1 );
        }
        return false;
    }

    // The identifiers a binding PATTERN declares (JS destructuring, Python targets, Go identifier lists).
    void patternNames( TSNode n, std::vector<std::string_view>& out, int depth = 0 ) const
    {
        if( ts_node_is_null( n ) || depth > 16 )
        {
            return;
        }
        const char* t = ts_node_type( n );
        if( kindIs( t, "identifier" ) || kindIs( t, "shorthand_property_identifier_pattern" ) )
        {
            out.push_back( text( n ) );
            return;
        }
        if( kindIs( t, "assignment_pattern" ) )
        {
            patternNames( child( n, m_fLeft ), out, depth + 1 );
            return;
        }
        if( kindIs( t, "pair_pattern" ) )
        {
            patternNames( child( n, m_fValue ), out, depth + 1 );
            return;
        }
        if( kindIs( t, "required_parameter" ) || kindIs( t, "optional_parameter" ) )
        {
            patternNames( child( n, m_fPattern ), out, depth + 1 );
            return;
        }
        if( kindIs( t, "object_pattern" ) || kindIs( t, "array_pattern" ) || kindIs( t, "rest_pattern" )
            || kindIs( t, "pattern_list" ) || kindIs( t, "tuple_pattern" ) || kindIs( t, "list_pattern" )
            || kindIs( t, "expression_list" ) || kindIs( t, "list_splat_pattern" ) || kindIs( t, "dictionary_splat_pattern" )
            || kindIs( t, "parenthesized_expression" ) )
        {
            ChildCursor c( n );
            forEachNamedChild( n, c.cur, [ & ]( TSNode k ) { patternNames( k, out, depth + 1 ); return true; } );
        }
    }

    // One declaring node's names, appended to `out` (the per-language harvest; see the header comment).
    void harvest( TSNode n, const char* t, std::vector<std::string_view>& out ) const
    {
        switch( m_fam )
        {
            case VrFam::C:
            {
                if( kindIs( t, "lambda_capture_specifier" ) )
                {
                    // C++ captures declare the lambda's names: `[key]`, `[&key]`, `[key = 3]` (lambda_capture_initializer).
                    ChildCursor c( n );
                    forEachNamedChild( n, c.cur, [ & ]( TSNode k )
                    {
                        const char* kt = ts_node_type( k );
                        if( kindIs( kt, "identifier" ) )
                        {
                            out.push_back( text( k ) );
                        }
                        else if( kindIs( kt, "lambda_capture_initializer" ) || kindIs( kt, "lambda_default_capture" ) )
                        {
                            const TSNode id = ts_node_named_child( k, 0 );
                            if( !ts_node_is_null( id ) && kindIs( ts_node_type( id ), "identifier" ) )
                            {
                                out.push_back( text( id ) );
                            }
                        }
                        return true;
                    } );
                }
                else if( kindIs( t, "structured_binding_declarator" ) )
                {
                    ChildCursor c( n );
                    forEachNamedChild( n, c.cur, [ & ]( TSNode k )
                    {
                        if( kindIs( ts_node_type( k ), "identifier" ) )
                        {
                            out.push_back( text( k ) );
                        }
                        return true;
                    } );
                }
                else if( kindIs( t, "declaration" ) || kindIs( t, "parameter_declaration" ) || kindIs( t, "for_range_loop" )
                         || kindIs( t, "field_declaration" )
                         || kindIs( t, "optional_parameter_declaration" ) || kindIs( t, "condition_clause" ) )
                {
                    ChildCursor c( n );
                    ts_tree_cursor_reset( &c.cur, n );
                    if( ts_tree_cursor_goto_first_child( &c.cur ) )
                    {
                        do
                        {
                            if( ts_tree_cursor_current_field_id( &c.cur ) == m_fDeclarator
                                && !declaresFunction( ts_tree_cursor_current_node( &c.cur ) ) )
                            {
                                const std::string_view nm = declaratorName( ts_tree_cursor_current_node( &c.cur ) );
                                if( !nm.empty() )
                                {
                                    out.push_back( nm );
                                }
                            }
                        }
                        while( ts_tree_cursor_goto_next_sibling( &c.cur ) );
                    }
                }
                break;
            }
            case VrFam::Js:
            {
                if( kindIs( t, "variable_declarator" ) )
                {
                    patternNames( child( n, m_fName ), out );
                }
                else if( kindIs( t, "formal_parameters" ) )
                {
                    ChildCursor c( n );
                    forEachNamedChild( n, c.cur, [ & ]( TSNode k ) { patternNames( k, out ); return true; } );
                }
                else if( kindIs( t, "arrow_function" ) )
                {
                    patternNames( child( n, m_fParameter ), out );
                }
                else if( kindIs( t, "catch_clause" ) )
                {
                    patternNames( child( n, m_fParameter ), out );
                }
                else if( kindIs( t, "for_in_statement" ) )
                {
                    patternNames( child( n, m_fLeft ), out );
                }
                break;
            }
            case VrFam::Py:
            {
                if( kindIs( t, "assignment" ) || kindIs( t, "augmented_assignment" ) || kindIs( t, "for_statement" )
                    || kindIs( t, "for_in_clause" ) )
                {
                    patternNames( child( n, m_fLeft ), out );
                }
                else if( kindIs( t, "named_expression" ) )
                {
                    patternNames( child( n, m_fName ), out );
                }
                else if( kindIs( t, "parameters" ) || kindIs( t, "lambda_parameters" ) )
                {
                    for( const std::string_view p : pyParamNames( n ) )
                    {
                        if( !p.empty() )
                        {
                            out.push_back( p );
                        }
                    }
                }
                else if( kindIs( t, "as_pattern_target" ) )
                {
                    patternNames( ts_node_named_child( n, 0 ), out );
                }
                else if( ( kindIs( t, "import_from_statement" ) || kindIs( t, "import_statement" ) ) && m_scopes.size() > 1 )
                {
                    // An import INSIDE a function binds a local; at file scope it is resolved through the import table.
                    ChildCursor c( n );
                    forEachNamedChild( n, c.cur, [ & ]( TSNode k )
                    {
                        const char* kt = ts_node_type( k );
                        if( kindIs( kt, "aliased_import" ) )
                        {
                            out.push_back( text( child( k, m_fAlias ) ) );
                        }
                        else if( kindIs( kt, "dotted_name" ) && ts_node_named_child_count( k ) > 0 )
                        {
                            out.push_back( text( ts_node_named_child( k, 0 ) ) );
                        }
                        return true;
                    } );
                }
                break;
            }
            case VrFam::Go:
            {
                if( kindIs( t, "parameter_declaration" ) || kindIs( t, "variadic_parameter_declaration" ) || kindIs( t, "var_spec" )
                    || kindIs( t, "const_spec" ) )
                {
                    ChildCursor c( n );
                    ts_tree_cursor_reset( &c.cur, n );
                    if( ts_tree_cursor_goto_first_child( &c.cur ) )
                    {
                        do
                        {
                            if( ts_tree_cursor_current_field_id( &c.cur ) == m_fName )
                            {
                                out.push_back( text( ts_tree_cursor_current_node( &c.cur ) ) );
                            }
                        }
                        while( ts_tree_cursor_goto_next_sibling( &c.cur ) );
                    }
                }
                else if( kindIs( t, "short_var_declaration" ) || kindIs( t, "range_clause" ) )
                {
                    patternNames( child( n, m_fLeft ), out );
                }
                break;
            }
            case VrFam::None: break;
        }
    }

    std::vector<std::string_view> pyParamNames( TSNode params ) const
    {
        std::vector<std::string_view> names;
        ChildCursor c( params );
        forEachNamedChild( params, c.cur, [ & ]( TSNode k )
        {
            const char* t = ts_node_type( k );
            if( kindIs( t, "identifier" ) )
            {
                names.push_back( text( k ) );
            }
            else if( kindIs( t, "default_parameter" ) || kindIs( t, "typed_default_parameter" ) )
            {
                names.push_back( text( child( k, m_fName ) ) );
            }
            else if( kindIs( t, "typed_parameter" ) || kindIs( t, "list_splat_pattern" ) || kindIs( t, "dictionary_splat_pattern" ) )
            {
                const TSNode id = ts_node_named_child( k, 0 );
                names.push_back( !ts_node_is_null( id ) && kindIs( ts_node_type( id ), "identifier" ) ? text( id ) : std::string_view() );
            }
            return true;
        } );
        return names;
    }

    // The positional parameter names of a function-like node, in order, and its own name.
    void functionSignature( TSNode fn, const char* t, VrScope& s ) const
    {
        switch( m_fam )
        {
            case VrFam::C:
            {
                TSNode d = child( fn, m_fDeclarator ), innermost {};
                for( int guard = 0; guard < 32 && !ts_node_is_null( d ); ++guard )
                {
                    const char* dt = ts_node_type( d );
                    if( kindIs( dt, "identifier" ) || kindIs( dt, "field_identifier" ) || kindIs( dt, "qualified_identifier" )
                        || kindIs( dt, "destructor_name" ) || kindIs( dt, "operator_name" ) )
                    {
                        s.fnName = text( d );
                        break;
                    }
                    if( kindIs( dt, "function_declarator" ) || kindIs( dt, "abstract_function_declarator" ) )
                    {
                        innermost = d;
                    }
                    TSNode next = child( d, m_fDeclarator );
                    d = ts_node_is_null( next ) ? ts_node_named_child( d, 0 ) : next;
                }
                const TSNode params = ts_node_is_null( innermost ) ? TSNode{} : child( innermost, m_fParameters );
                if( !ts_node_is_null( params ) )
                {
                    ChildCursor c( params );
                    forEachNamedChild( params, c.cur, [ & ]( TSNode k )
                    {
                        if( kindIs( ts_node_type( k ), "parameter_declaration" ) || kindIs( ts_node_type( k ), "optional_parameter_declaration" ) )
                        {
                            s.params.push_back( declaratorName( child( k, m_fDeclarator ) ) );
                        }
                        return true;
                    } );
                }
                break;
            }
            case VrFam::Js:
            {
                s.fnName = text( child( fn, m_fName ) );
                const TSNode single = kindIs( t, "arrow_function" ) ? child( fn, m_fParameter ) : TSNode{};
                if( !ts_node_is_null( single ) )
                {
                    s.params.push_back( text( single ) );
                    break;
                }
                const TSNode params = child( fn, m_fParameters );
                if( !ts_node_is_null( params ) )
                {
                    ChildCursor c( params );
                    forEachNamedChild( params, c.cur, [ & ]( TSNode k )
                    {
                        if( ts_node_is_extra( k ) )
                        {
                            return true;
                        }
                        std::vector<std::string_view> nm;
                        patternNames( k, nm );
                        s.params.push_back( nm.size() == 1 ? nm[0] : std::string_view() );
                        return true;
                    } );
                }
                break;
            }
            case VrFam::Py:
            {
                s.fnName = text( child( fn, m_fName ) );
                const TSNode params = child( fn, m_fParameters );
                if( !ts_node_is_null( params ) )
                {
                    s.params = pyParamNames( params );
                }
                break;
            }
            case VrFam::Go:
            {
                s.fnName = text( child( fn, m_fName ) );
                const TSNode params = child( fn, m_fParameters );
                if( !ts_node_is_null( params ) )
                {
                    ChildCursor c( params );
                    forEachNamedChild( params, c.cur, [ & ]( TSNode k )
                    {
                        std::vector<std::string_view> nm;
                        harvest( k, ts_node_type( k ), nm );
                        if( nm.empty() )
                        {
                            s.params.push_back( {} );
                        }
                        for( const std::string_view p : nm )
                        {
                            s.params.push_back( p );
                        }
                        return true;
                    } );
                }
                break;
            }
            case VrFam::None: break;
        }
    }

    // A scope as it opens, with the names that are in scope before the walk reaches their declaring node: a function's
    // parameters; a C++ class's members (complete-class context); a Python comprehension's for-clause targets.
    VrScope openScope( TSNode n, const char* kind, ScopeKind sk ) const
    {
        VrScope s;
        s.node       = n;
        s.isFunction = sk == ScopeKind::Function;
        s.isClass    = sk == ScopeKind::Class;
        if( s.isFunction )
        {
            functionSignature( n, kind, s );
        }
        else if( s.isClass && m_fam == VrFam::C && !ts_node_is_null( fieldChild( n, NodeField::Body ) ) )
        {
            // A C++ class body is a complete-class context: a data member declared BELOW a member function is still in
            // scope inside it (`int get() { return total; } int total = 0;`), so the members are read as the class opens.
            const TSNode body = fieldChild( n, NodeField::Body );
            ChildCursor  c( body );
            forEachNamedChild( body, c.cur, [ & ]( TSNode k )
            {
                const char* kt = ts_node_type( k );
                if( kindIs( kt, "field_declaration" ) )
                {
                    harvest( k, kt, s.decls );
                }
                return true;
            } );
        }
        else if( sk == ScopeKind::Block )
        {
            ChildCursor c( n );
            forEachNamedChild( n, c.cur, [ & ]( TSNode k )
            {
                if( kindIs( ts_node_type( k ), "for_in_clause" ) )
                {
                    patternNames( child( k, m_fLeft ), s.decls );
                }
                return true;
            } );
        }
        return s;
    }

    // ── the walk ───────────────────────────────────────────────────────────────────────────────────────
    void enter( TSNode n, TSFieldId field )
    {
        VrAnc a;
        a.node  = n;
        a.kind  = ts_node_type( n );
        a.field = field;
        if( !m_anc.empty() && ts_node_is_named( n ) && !ts_node_is_extra( n ) )
        {
            a.namedIndex = m_anc.back().childNamed++;
        }
        // DECLARE ON ENCOUNTER (one walk, not a pre-pass per scope — the pre-pass doubled the node visits and cost
        // ~10% of a cold Python/JS run): every scope this walk tracks is opened here, and every declaring node adds
        // its names to the innermost open scope as it is entered, i.e. before the uses below it are visited. The
        // languages declare before use (C, Go, JS let/const; a Python local used before its assignment is an
        // UnboundLocalError), with one exception handled where it opens: a Python comprehension's element precedes
        // its `for` clause, so a Block scope pre-reads its for-clause targets.
        const ScopeKind sk = m_anc.empty() ? ScopeKind::None : scopeKindOf( a.kind );
        if( sk != ScopeKind::None )
        {
            m_scopes.push_back( openScope( n, a.kind, sk ) );
            a.opensScope = true;
        }
        harvest( n, a.kind, m_scopes.back().decls );
        m_anc.push_back( a );
        const std::size_t i = m_anc.size() - 1;
        if( m_fam == VrFam::Py && kindIs( a.kind, "decorated_definition" ) )
        {
            emitDecorators( n );
        }
        else if( isIdentifierKind( a.kind ) )
        {
            valueRefAt( i );
        }
        else if( isCallKind( a.kind ) )
        {
            throughAt( n );
        }
    }

    void leave()
    {
        ASSUME( !m_anc.empty(), "leave() pairs with an enter(): the walk never leaves past the root" );
        ASSUME( !m_anc.back().opensScope || m_scopes.size() > 1, "a node that opened a scope has one above the file scope to close" );
        if( m_anc.back().opensScope )
        {
            VrScope& s = m_scopes.back();
            vrSortUnique( s.fed );   // as the file-scope filter: membership only, s.pending keeps its order
            for( RawRef& t : s.pending )
            {
                if( std::ranges::binary_search( s.fed, t.name ) )
                {
                    m_out.push_back( std::move( t ) );
                }
            }
            m_scopes.pop_back();
        }
        m_anc.pop_back();
    }

    // The innermost non-file scope declaring `name` (index into m_scopes), or 0 when none does.
    std::size_t declaringScope( std::string_view name ) const noexcept
    {
        for( std::size_t k = m_scopes.size(); k > 1; --k )
        {
            const VrScope& sc = m_scopes[k - 1];
            if( sc.isClass && k != m_scopes.size() && m_lang != Lang::Cpp )
            {
                continue;   // a Python/JS class attribute is not visible inside the class's methods; a C++ data member IS
            }
            if( std::ranges::find( sc.decls, name ) != sc.decls.end() )
            {
                return k - 1;
            }
        }
        return 0;
    }

    // ── value positions ────────────────────────────────────────────────────────────────────────────────
    struct Slot
    {
        std::string into;          // the slot as written (into=)
        std::string container;     // the simple container identifier, "" when none
        std::string key;           // the normalised key
        char        scope = 'x';
        std::uint16_t argIndex = 0;
        bool          isArg = false;
    };

    std::string_view opText( TSNode n ) const noexcept
    {
        const TSNode op = child( n, m_fOperator );
        if( !ts_node_is_null( op ) )
        {
            return text( op );
        }
        const TSNode mid = ts_node_child( n, 1 );   // binary nodes have exactly three children: left op right
        return text( mid );
    }

    // Is anc[i] a pass-through wrapper whose own position is the value's (parentheses, `&f`, a ternary branch…)?
    bool transparent( std::size_t i ) const noexcept
    {
        const VrAnc& p = m_anc[i - 1];
        const VrAnc& c = m_anc[i];
        const char*  t = p.kind;
        if( kindIs( t, "parenthesized_expression" ) || kindIs( t, "as_expression" ) || kindIs( t, "satisfies_expression" )
            || kindIs( t, "non_null_expression" ) || kindIs( t, "literal_element" ) || kindIs( t, "expression_list" )
            || kindIs( t, "type_assertion" ) )
        {
            return true;
        }
        if( kindIs( t, "pointer_expression" ) )
        {
            const TSNode first = ts_node_child( p.node, 0 );
            return text( first ) == "&";
        }
        if( kindIs( t, "conditional_expression" ) || kindIs( t, "ternary_expression" ) )
        {
            if( m_fam == VrFam::Py )
            {
                return c.namedIndex != 1;   // `a if cond else b`: the middle named child is the condition
            }
            return c.field != 0 && ( c.field == m_fConsequence || c.field == m_fAlternative );
        }
        return false;
    }

    // The callee of the call whose argument list is anc[j] (the list itself), as written, plus its bare name.
    std::pair<std::string, std::string> calleeOf( std::size_t j ) const
    {
        if( j == 0 )
        {
            return {};
        }
        const TSNode call = m_anc[j - 1].node;
        TSNode       f    = child( call, m_fFunction );
        if( ts_node_is_null( f ) )
        {
            f = child( call, m_fConstructor );
        }
        if( ts_node_is_null( f ) )
        {
            return {};
        }
        std::string bare = kindIs( ts_node_type( f ), "identifier" ) ? std::string( text( f ) ) : std::string();
        return { vrClean( text( f ) ), std::move( bare ) };
    }

    // The container a LITERAL (anc[j]) is bound to: its written text, and the simple identifier when it is one.
    // Climbs through nested literals (`X.a.b`), declarators, assignments and argument lists.
    std::pair<std::string, std::string> containerOf( std::size_t j, int depth = 0 ) const
    {
        while( j > 0 && transparent( j ) )
        {
            --j;
        }
        if( j == 0 || depth > 8 )
        {
            return { "(literal)", "" };
        }
        const VrAnc& p  = m_anc[j - 1];
        const VrAnc& c  = m_anc[j];
        const char*  pt = p.kind;
        if( kindIs( pt, "composite_literal" ) || kindIs( pt, "compound_literal_expression" ) )
        {
            return containerOf( j - 1, depth + 1 );   // Go `T{…}` / C `(T){…}`: the literal is the parent's
        }
        if( kindIs( pt, "init_declarator" ) || kindIs( pt, "variable_declarator" ) )
        {
            const std::string_view nm = kindIs( pt, "init_declarator" ) ? declaratorName( child( p.node, m_fDeclarator ) )
                                                                         : text( child( p.node, m_fName ) );
            return { std::string( nm ), std::string( nm ) };
        }
        if( kindIs( pt, "var_spec" ) || kindIs( pt, "short_var_declaration" ) || kindIs( pt, "assignment_statement" ) )
        {
            const std::string_view nm = nthName( p.node, kindIs( pt, "var_spec" ), c.namedIndex );
            return { std::string( nm ), std::string( nm ) };
        }
        if( ( kindIs( pt, "assignment_expression" ) || kindIs( pt, "assignment" ) ) && c.field == m_fRight )
        {
            const TSNode lhs = child( p.node, m_fLeft );
            const std::string w = vrClean( text( lhs ) );
            return { w, kindIs( ts_node_type( lhs ), "identifier" ) ? w : std::string() };
        }
        if( kindIs( pt, "pair" ) || kindIs( pt, "initializer_pair" ) || kindIs( pt, "keyed_element" ) )
        {
            if( j >= 2 )
            {
                const auto [ outer, outerId ] = containerOf( j - 2, depth + 1 );
                std::string into, key;
                keyOf( p, into, key );
                return { outer + into, std::string() };
            }
        }
        if( kindIs( pt, "initializer_list" ) || kindIs( pt, "array" ) || kindIs( pt, "list" ) || kindIs( pt, "tuple" )
            || kindIs( pt, "set" ) || kindIs( pt, "literal_value" ) )
        {
            const auto [ outer, outerId ] = containerOf( j - 1, depth + 1 );
            return { outer + "[" + std::to_string( c.namedIndex ) + "]", std::string() };
        }
        if( kindIs( pt, "argument_list" ) || kindIs( pt, "arguments" ) )
        {
            const auto [ callee, bare ] = calleeOf( j - 1 );
            return { callee + "#arg" + std::to_string( c.namedIndex ), std::string() };
        }
        if( kindIs( pt, "return_statement" ) )
        {
            return { "(return)", "" };
        }
        return { "(literal)", "" };
    }

    // The n-th declared name of a Go var_spec / short_var_declaration / assignment (the left side).
    std::string_view nthName( TSNode decl, bool isVarSpec, std::uint32_t valueIndex ) const
    {
        std::vector<std::string_view> names;
        if( isVarSpec )
        {
            harvest( decl, "var_spec", names );
        }
        else
        {
            patternNames( child( decl, m_fLeft ), names );
        }
        if( names.empty() )
        {
            return {};
        }
        return valueIndex < names.size() ? names[ valueIndex ] : names.back();
    }

    // The written key suffix (`.open`, `["get"]`) and its normalised match key (`.open`, `[get]`) of a keyed element.
    void keyOf( const VrAnc& pair, std::string& into, std::string& key ) const
    {
        const char* pt = pair.kind;
        TSNode      k {};
        if( kindIs( pt, "initializer_pair" ) )
        {
            k = child( pair.node, m_fDesignator );
            if( ts_node_is_null( k ) )
            {
                k = ts_node_named_child( pair.node, 0 );
            }
            const char* kt = ts_node_type( k );
            if( kindIs( kt, "field_designator" ) )
            {
                const std::string nm( text( ts_node_named_child( k, 0 ) ) );
                into = "." + nm;
                key  = "." + nm;
                return;
            }
            const std::string w( text( ts_node_named_child( k, 0 ) ) );
            into = "[" + w + "]";
            key  = "[" + w + "]";
            return;
        }
        if( kindIs( pt, "keyed_element" ) )
        {
            k = ts_node_named_child( pair.node, 0 );
            if( !ts_node_is_null( k ) && kindIs( ts_node_type( k ), "literal_element" ) )
            {
                k = ts_node_named_child( k, 0 );
            }
        }
        else
        {
            k = child( pair.node, m_fKey );
        }
        if( ts_node_is_null( k ) )
        {
            return;
        }
        const char*            kt = ts_node_type( k );
        const std::string_view w  = text( k );
        if( vrKeyKind( kt ) == VrKeyKind::String )
        {
            const std::string content( vrStringContent( w ) );
            if( m_fam == VrFam::Js )
            {
                into = "." + vrClean( content );   // capped like every other written slot (the Python branch below)
                key  = "." + content;
            }
            else
            {
                into = "[" + vrClean( w ) + "]";
                key  = "[" + content + "]";
            }
            return;
        }
        if( vrKeyKind( kt ) == VrKeyKind::Number )
        {
            into = "[" + std::string( w ) + "]";
            key  = "[" + std::string( w ) + "]";
            return;
        }
        if( m_fam == VrFam::Py )
        {
            into = "[" + vrClean( w ) + "]";   // a non-literal dict key: the value is reached through it, unknowable here
            key  = "*";
            return;
        }
        into = "." + std::string( w );           // JS property_identifier / Go struct field name
        key  = "." + std::string( w );
    }

    void valueRefAt( std::size_t i )
    {
        EXPECTS( i < m_anc.size(), "the identifier is on the ancestor stack" );
        if( i == 0 )
        {
            return;
        }
        const std::string_view name = text( m_anc[i].node );
        if( name.empty() )
        {
            return;
        }
        // The shadow test FIRST: most identifiers in a value position are a parameter or local (`f(x)`), and the
        // position's slot text (callee, container) is only worth building for a name that can still be a function.
        if( declaringScope( name ) != 0 )
        {
            return;   // a parameter or local of that name hides the function
        }
        std::size_t j = i;
        while( j > 1 && transparent( j ) )
        {
            --j;
        }
        Slot s;
        if( !classify( i, j, s ) )
        {
            return;
        }
        const bool fileShadow = std::ranges::find( m_scopes.front().decls, name ) != std::ranges::end( m_scopes.front().decls );

        if( !s.container.empty() && ( s.scope == 'f' || s.scope == 'l' ) )
        {
            const std::size_t d = declaringScope( s.container );
            if( d != 0 )
            {
                s.scope = 'l';
                m_scopes[d].fed.push_back( s.container );
            }
            else
            {
                s.scope = 'f';
                m_fileFed.push_back( s.container );
            }
        }

        RawRef r;
        r.fileId        = m_fileId;
        r.startByte     = ts_node_start_byte( m_anc[i].node );
        r.line          = ts_node_start_point( m_anc[i].node ).row + 1;
        r.lang          = m_lang;
        r.role          = RefRole::Value;
        r.name          = std::string( name );
        r.qualifier     = std::string{ s.scope, fileShadow ? '1' : '0' };
        r.recvVar       = std::move( s.container );
        r.composeRel    = std::move( s.key );
        r.fieldName     = std::move( s.into );
        r.argCount      = s.argIndex;
        r.argCountKnown = s.isArg;
        m_out.push_back( std::move( r ) );
    }

    // Classify the value position of identifier anc[i], whose effective position (after pass-through wrappers)
    // is anc[j]. Returns false for every position that is not a value use.
    bool classify( std::size_t i, std::size_t j, Slot& s ) const
    {
        const VrAnc& self = m_anc[i];
        const VrAnc& c    = m_anc[j];
        const VrAnc& p    = m_anc[j - 1];
        const char*  pt   = p.kind;

        // JS shorthand `{ f }`: the identifier IS the pair.
        if( kindIs( self.kind, "shorthand_property_identifier" ) )
        {
            if( i != j || !kindIs( pt, "object" ) )
            {
                return false;
            }
            const auto [ cont, id ] = containerOf( j - 1 );
            s.into = cont + "." + std::string( text( self.node ) );
            s.container = id;
            s.key = "." + std::string( text( self.node ) );
            s.scope = id.empty() ? 'x' : 'f';
            return true;
        }
        // keyed elements: the VALUE side only (a key or field NAME is never a value use) …
        if( kindIs( pt, "pair" ) || kindIs( pt, "initializer_pair" ) || kindIs( pt, "keyed_element" ) )
        {
            bool isValue = false;
            if( kindIs( pt, "keyed_element" ) )
            {
                isValue = c.namedIndex == 1;
            }
            else
            {
                isValue = c.field == m_fValue;
            }
            if( !isValue )
            {
                // … except a Python dict KEY that is itself a function (`{handler: 1}`): the function object is the key.
                if( m_fam == VrFam::Py && kindIs( pt, "pair" ) && c.field == m_fKey && j >= 2 )
                {
                    const auto [ cont, id ] = containerOf( j - 2 );
                    s.into = cont + "{}";
                    s.container = id;
                    s.key = "{}";
                    s.scope = id.empty() ? 'x' : 'f';
                    return true;
                }
                return false;
            }
            if( j < 2 )
            {
                return false;
            }
            const auto [ cont, id ] = containerOf( j - 2 );
            std::string into, key;
            keyOf( p, into, key );
            s.into = cont + into;
            s.container = id;
            s.key = key;
            s.scope = id.empty() ? 'x' : 'f';
            return true;
        }
        // JS computed key `{ [f]: 1 }`: the function is coerced to a KEY.
        if( kindIs( pt, "computed_property_name" ) && j >= 4 )
        {
            const auto [ cont, id ] = containerOf( j - 3 );
            s.into = cont + "{}";
            s.container = id;
            s.key = "{}";
            s.scope = id.empty() ? 'x' : 'f';
            return true;
        }
        // positional elements of an initialiser / array / list / tuple / set / Go literal
        if( kindIs( pt, "initializer_list" ) || kindIs( pt, "array" ) || kindIs( pt, "list" ) || kindIs( pt, "tuple" )
            || kindIs( pt, "set" ) || kindIs( pt, "literal_value" ) )
        {
            const auto [ cont, id ] = containerOf( j - 1 );
            s.into = cont + "[" + std::to_string( c.namedIndex ) + "]";
            s.container = id;
            s.key = "[" + std::to_string( c.namedIndex ) + "]";
            s.scope = id.empty() ? 'x' : 'f';
            return true;
        }
        // call arguments
        if( kindIs( pt, "argument_list" ) || kindIs( pt, "arguments" ) )
        {
            const auto [ callee, bare ] = calleeOf( j - 1 );
            if( callee.empty() )
            {
                return false;
            }
            std::uint32_t pos = c.namedIndex;
            if( m_fam == VrFam::Py )
            {
                pos = pyPositionalIndex( p.node, c.node );
            }
            s.into = callee + "#arg" + std::to_string( pos );
            s.container = bare;
            s.key = "#" + std::to_string( pos );
            s.scope = bare.empty() ? 'x' : 'a';
            s.argIndex = static_cast<std::uint16_t>( std::min<std::uint32_t>( pos, 0xFFFFu ) );
            s.isArg = true;
            return true;
        }
        // Python keyword argument value `f(target=fn)`
        if( kindIs( pt, "keyword_argument" ) )
        {
            if( c.field != m_fValue || j < 3 )
            {
                return false;   // the keyword LABEL is never a value use
            }
            const auto [ callee, bare ] = calleeOf( j - 2 );
            const std::string kw( text( child( p.node, m_fName ) ) );
            if( callee.empty() || kw.empty() )
            {
                return false;
            }
            s.into = callee + "#" + kw;
            s.container = bare;
            s.key = "#" + kw;
            s.scope = bare.empty() ? 'x' : 'a';
            return true;
        }
        // parameter defaults: Python `def f(cb=fn)`, JS `function f(cb = fn)`
        if( ( kindIs( pt, "default_parameter" ) || kindIs( pt, "typed_default_parameter" ) ) && c.field == m_fValue )
        {
            return paramDefault( std::string( text( child( p.node, m_fName ) ) ), s );
        }
        if( kindIs( pt, "assignment_pattern" ) && c.field == m_fRight && j >= 2 && kindIs( m_anc[j - 2].kind, "formal_parameters" ) )
        {
            return paramDefault( std::string( text( child( p.node, m_fLeft ) ) ), s );
        }
        // declarators and assignments: the value lands in the left-hand side
        if( kindIs( pt, "init_declarator" ) && c.field == m_fValue )
        {
            const std::string nm( declaratorName( child( p.node, m_fDeclarator ) ) );
            s.into = nm;
            s.container = nm;
            s.scope = 'f';
            return !nm.empty();
        }
        if( kindIs( pt, "variable_declarator" ) && c.field == m_fValue )
        {
            const TSNode nmNode = child( p.node, m_fName );
            if( ts_node_is_null( nmNode ) || !kindIs( ts_node_type( nmNode ), "identifier" ) )
            {
                return false;
            }
            s.into = std::string( text( nmNode ) );
            s.container = s.into;
            s.scope = 'f';
            return true;
        }
        if( kindIs( pt, "var_spec" ) || kindIs( pt, "short_var_declaration" ) || kindIs( pt, "assignment_statement" ) )
        {
            if( kindIs( pt, "var_spec" ) ? c.field != m_fValue : c.field != m_fRight )
            {
                return false;
            }
            std::uint32_t idx = 0;   // the value's position in the right-hand expression_list
            for( std::size_t k = i; k > j; --k )
            {
                if( kindIs( m_anc[k - 1].kind, "expression_list" ) )
                {
                    idx = m_anc[k].namedIndex;
                    break;
                }
            }
            const std::string nm( nthName( p.node, kindIs( pt, "var_spec" ), idx ) );
            s.into = nm;
            s.container = nm;
            s.scope = 'f';
            return !nm.empty();
        }
        if( ( kindIs( pt, "assignment_expression" ) || kindIs( pt, "assignment" ) ) && c.field == m_fRight )
        {
            const TSNode lhs = child( p.node, m_fLeft );
            const char*  lt  = ts_node_type( lhs );
            s.into = vrClean( text( lhs ) );
            if( kindIs( lt, "identifier" ) )
            {
                s.container = s.into;
                s.scope = 'f';
                return true;
            }
            TSNode obj {}, prop {};
            if( kindIs( lt, "field_expression" ) )
            {
                obj = child( lhs, m_fArgument );  prop = child( lhs, m_fField );
            }
            else if( kindIs( lt, "member_expression" ) )
            {
                obj = child( lhs, m_fObject );    prop = child( lhs, m_fProperty );
            }
            else if( kindIs( lt, "attribute" ) )
            {
                obj = child( lhs, m_fObject );    prop = child( lhs, m_fAttribute );
            }
            else if( kindIs( lt, "selector_expression" ) )
            {
                obj = child( lhs, m_fOperand );   prop = child( lhs, m_fField );
            }
            if( !ts_node_is_null( obj ) && !ts_node_is_null( prop ) && kindIs( ts_node_type( obj ), "identifier" ) )
            {
                s.container = std::string( text( obj ) );
                s.key = "." + std::string( text( prop ) );
                s.scope = 'f';
            }
            return !s.into.empty();
        }
        if( kindIs( pt, "return_statement" ) )
        {
            s.into = "(return)";
            return true;
        }
        if( kindIs( pt, "binary_expression" ) )
        {
            const std::string_view op = opText( p.node );
            if( op == "==" || op == "!=" || op == "===" || op == "!==" )
            {
                s.into = "(compare)";
                return true;
            }
            return false;
        }
        if( kindIs( pt, "comparison_operator" ) )
        {
            s.into = "(compare)";
            return true;
        }
        // JSX `<button onClick={handler}>`
        if( kindIs( pt, "jsx_expression" ) && j >= 3 && kindIs( m_anc[j - 2].kind, "jsx_attribute" ) )
        {
            const TSNode attr = m_anc[j - 2].node;
            const TSNode elem = m_anc[j - 3].node;
            const std::string attrName( text( ts_node_named_child( attr, 0 ) ) );
            const std::string elemName( text( child( elem, m_fName ) ) );
            if( attrName.empty() )
            {
                return false;
            }
            s.into = ( elemName.empty() ? std::string( "(jsx)" ) : elemName ) + "." + attrName;
            return true;
        }
        return false;
    }

    bool paramDefault( std::string param, Slot& s ) const
    {
        // The default sits inside the function's own scope: the innermost function scope is the owner.
        for( std::size_t k = m_scopes.size(); k > 1; --k )
        {
            const VrScope& sc = m_scopes[k - 1];
            if( sc.isFunction )
            {
                if( param.empty() )
                {
                    return false;
                }
                const std::string fn = sc.fnName.empty() ? std::string( "(fn)" ) : std::string( sc.fnName );
                s.into = fn + "#" + param;
                s.container = fn;
                s.key = "#" + param;
                s.scope = 'p';
                return true;
            }
        }
        return false;
    }

    // A Python positional argument's index: named children before it that are not keyword arguments.
    std::uint32_t pyPositionalIndex( TSNode args, TSNode arg ) const
    {
        std::uint32_t pos = 0;
        bool          found = false;
        ChildCursor   c( args );
        forEachNamedChild( args, c.cur, [ & ]( TSNode k )
        {
            if( ts_node_eq( k, arg ) )
            {
                found = true;
                return false;
            }
            if( !ts_node_is_extra( k ) && !kindIs( ts_node_type( k ), "keyword_argument" ) )
            {
                ++pos;
            }
            return true;
        } );
        return found ? pos : 0;
    }

    // ── decorators (Python): the decorated def is handed to the decorator as a value ───────────────────
    void emitDecorators( TSNode decorated )
    {
        const TSNode def = child( decorated, m_fDefinition );
        if( ts_node_is_null( def ) || !kindIs( ts_node_type( def ), "function_definition" ) )
        {
            return;   // class decorators: classes are out of scope (floor F6)
        }
        const std::string_view fnName = text( child( def, m_fName ) );
        if( fnName.empty() )
        {
            return;
        }
        ChildCursor c( decorated );
        forEachNamedChild( decorated, c.cur, [ & ]( TSNode k )
        {
            if( !kindIs( ts_node_type( k ), "decorator" ) )
            {
                return true;
            }
            TSNode e = ts_node_named_child( k, 0 );
            if( !ts_node_is_null( e ) && kindIs( ts_node_type( e ), "call" ) )
            {
                e = child( e, m_fFunction );
            }
            if( ts_node_is_null( e ) )
            {
                return true;
            }
            RawRef r;
            r.fileId    = m_fileId;
            r.startByte = ts_node_start_byte( k );
            r.line      = ts_node_start_point( k ).row + 1;
            r.lang      = m_lang;
            r.role      = RefRole::Value;
            r.name      = std::string( fnName );
            r.qualifier = "x0";
            r.fieldName = "@" + vrClean( text( e ) );
            m_out.push_back( std::move( r ) );
            return true;
        } );
    }

    // ── calls through a value ──────────────────────────────────────────────────────────────────────────
    void throughAt( TSNode call )
    {
        if( m_fam == VrFam::Go && kindIs( ts_node_type( call ), "type_conversion_expression" ) )
        {
            const TSNode gt = child( call, m_fType );
            if( !ts_node_is_null( gt ) && kindIs( ts_node_type( gt ), "generic_type" ) )
            {
                emitThrough( call, child( gt, m_fType ), gt, "*", false );
            }
            return;
        }
        const TSNode f = child( call, m_fFunction );
        if( ts_node_is_null( f ) )
        {
            return;
        }
        const char* ft = ts_node_type( f );
        TSNode      obj {};
        std::string key;
        if( kindIs( ft, "identifier" ) )
        {
            obj = f;
        }
        else if( kindIs( ft, "field_expression" ) || kindIs( ft, "member_expression" ) || kindIs( ft, "selector_expression" ) )
        {
            obj = kindIs( ft, "field_expression" ) ? child( f, m_fArgument ) : kindIs( ft, "member_expression" ) ? child( f, m_fObject ) : child( f, m_fOperand );
            const TSNode prop = kindIs( ft, "field_expression" ) || kindIs( ft, "selector_expression" ) ? child( f, m_fField ) : child( f, m_fProperty );
            key = "." + std::string( text( prop ) );
        }
        else if( kindIs( ft, "subscript_expression" ) || kindIs( ft, "subscript" ) || kindIs( ft, "index_expression" ) )
        {
            obj = kindIs( ft, "subscript_expression" ) ? ( m_fam == VrFam::Js ? child( f, m_fObject ) : child( f, m_fArgument ) )
                : kindIs( ft, "subscript" ) ? child( f, m_fValue ) : child( f, m_fOperand );
            TSNode idx = kindIs( ft, "subscript" ) ? child( f, m_fSubscript ) : child( f, m_fIndex );
            if( !ts_node_is_null( idx ) && kindIs( ts_node_type( idx ), "subscript_argument_list" ) )
            {
                idx = ts_node_named_child( idx, 0 );
            }
            const char* it = ts_node_is_null( idx ) ? "" : ts_node_type( idx );
            if( !ts_node_is_null( idx ) && vrKeyKind( it ) == VrKeyKind::String )
            {
                const std::string content( vrStringContent( text( idx ) ) );
                key = m_fam == VrFam::Js ? "." + content : "[" + content + "]";
            }
            else if( !ts_node_is_null( idx ) && vrKeyKind( it ) == VrKeyKind::Number )
            {
                key = "[" + std::string( text( idx ) ) + "]";
            }
            else
            {
                key = "*";
            }
        }
        else
        {
            return;
        }
        if( ts_node_is_null( obj ) || !kindIs( ts_node_type( obj ), "identifier" ) )
        {
            return;
        }
        if( m_fam == VrFam::Py && key.size() > 0 && key[0] == '.' )
        {
            return;   // a Python attribute call is a method call, never a dict-slot lookup
        }
        emitThrough( call, obj, f, std::move( key ), kindIs( ft, "identifier" ) );
    }

    // Record one call through the container `obj` (written callee `f`), routed by where `obj` is declared.
    void emitThrough( TSNode call, TSNode obj, TSNode f, std::string key, bool bareCall )
    {
        if( ts_node_is_null( obj ) )
        {
            return;
        }
        const std::string_view x = text( obj );
        RawRef r;
        r.fileId    = m_fileId;
        r.startByte = ts_node_start_byte( call );
        r.line      = ts_node_start_point( call ).row + 1;
        r.lang      = m_lang;
        r.role      = RefRole::Through;
        r.name      = std::string( x );
        r.composeRel = std::move( key );
        r.fieldName = vrClean( text( f ) );

        const std::size_t d = declaringScope( x );
        if( d != 0 )
        {
            VrScope& sc = m_scopes[d];
            if( sc.isFunction && bareCall )
            {
                for( std::size_t pi = 0; pi < sc.params.size(); ++pi )
                {
                    if( sc.params[pi] == x )
                    {
                        r.qualifier     = "p";
                        r.argCount      = static_cast<std::uint16_t>( std::min<std::size_t>( pi, 0xFFFFu ) );
                        r.argCountKnown = true;
                        m_out.push_back( std::move( r ) );
                        return;
                    }
                }
            }
            r.qualifier = "l";
            sc.pending.push_back( std::move( r ) );
            return;
        }
        // Not declared in any enclosing function: a file-scope container — declared above, or BELOW this function
        // (a Python/JS table usually follows the functions that index it). The file-end filter keeps it only when this
        // file fed that container a function value.
        r.qualifier = "f";
        m_filePending.push_back( std::move( r ) );
    }

    VrFam                          m_fam;
    Lang                           m_lang;
    std::uint32_t                  m_fileId;
    std::string_view               m_src;
    std::vector<RawRef>&           m_out;
    std::vector<VrScope>           m_scopes;
    std::vector<VrAnc>             m_anc;
    std::vector<std::string>       m_fileFed;
    std::vector<RawRef>            m_filePending;
    TSFieldId m_fValue = 0, m_fKey = 0, m_fLeft = 0, m_fRight = 0, m_fFunction = 0, m_fName = 0, m_fDeclarator = 0;
    TSFieldId m_fConsequence = 0, m_fAlternative = 0, m_fParameters = 0, m_fParameter = 0, m_fObject = 0, m_fProperty = 0, m_fField = 0;
    TSFieldId m_fArgument = 0, m_fOperand = 0, m_fAttribute = 0, m_fOperator = 0, m_fPattern = 0, m_fDefinition = 0;
    TSFieldId m_fConstructor = 0, m_fType = 0, m_fIndex = 0, m_fSubscript = 0, m_fDesignator = 0, m_fAlias = 0;
};

// The pass's entry point: one file's value references and calls-through-a-value, appended to `refs`. Inert on a
// language outside the armed set (C, C++, JavaScript/JSX, TypeScript/TSX, Python, Go).
inline void captureValueRefs( Lang lang, std::uint32_t fileId, std::string_view src, TSNode root, std::vector<RawRef>& refs )
{
    const VrFam fam = valueRefFamily( lang );
    if( fam == VrFam::None || ts_node_is_null( root ) )
    {
        return;
    }
    PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: value references" );
    ValueRefWalk walk( fam, lang, fileId, src, refs );
    walk.run( root );
}

}   // namespace

}   // namespace rw
