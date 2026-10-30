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
//   Slot typing (C family, IX-1 slot-type join; model.h RefRole::Value / Through): a Value row whose slot is a struct field
//            (a designated `.f = fn`, a positional entry of a struct literal this file defines the struct of, a field
//            assignment `x->a.f = fn`) carries memberPath = the field chain and memberCtor = the object's declared struct type;
//            a call through a field (`x->f( … )`, `x->a->f( … )`, `t[ i ].f( … )`) is a Through with qualifier
//            kValueRefSlotCallScope ('s'), name = the root x, memberCtor = x's declared type ("" when no scope declares x),
//            memberPath = the chain; and every struct field of a struct type, and every typedef of a struct, is a slot FACT
//            (role Value, qualifier kValueRefSlotFactScope 't', name ""): recvVar = the owner, composeRel = the field
//            ("" = a typedef alias), memberCtor = the field's type. An anonymous struct type is "@LINE" (its own file only);
//            an anonymous struct a typedef names is that name.
//   Depth cut (role Value, at most one per file, after its rows): name="" (no identifier is empty); qualifier="d"
//            (model.h kValueRefDepthCutScope); argCount=the subtrees kVrMaxDepth stopped the walk above (saturating);
//            startByte/line=the first one. Not a row: valuerefindex.h counts it, and every answer that reads value
//            references discloses it (value_refs_depth_capped= / value_refs_depth_at=), except --quality-delta's dead kind
//            and its value-ref-excluded= count, --verify uses()/unused() (count= is a floor there) and the LSP
//            references/hover handlers (named deferrals).
// A local/file Through survives only when the same scope fed that container a function value (the filter at
// scope exit / file end), so an ordinary `x.m()` adds nothing; a parameter Through always survives — its
// values arrive from callers elsewhere.
//
// FLOORS (stated in the legend and pinned by recallshapecheck; this walk's families — Rust records its own slot rows,
// ingest_rustslots.h): a member or qualified value (obj.f, self.f, ns::f; C++ `&Cls::m` IS a row: memberPointerValueAt) and a function as the OBJECT of a member access (f.bind, f.name) are not rows; an import
// alias is a local binding; a macro body is opaque; classes are not functions; Python attribute calls never
// count as a call through a dict; nodes deeper than kVrMaxDepth are not visited — DISCLOSED, never silent: the file's
// depth-cut record (below) makes value_refs= / --dead-code say the count is a floor and name the first cut site.

namespace rw
{

namespace
{

using VrFam = ValueRefFamily;   // model.h: the one armed-language table the resolver indexes too

inline constexpr std::uint32_t kVrMaxDepth   = 512;   // the value-uses pass's own depth guard (ingest_sidecap.h kSideDepthUses); a cut is disclosed as value_refs_depth_capped= (valuerefs.h)
inline constexpr std::size_t   kVrTextCap    = 96;    // a written slot / callee longer than this is cut with "…"

// IX-1: a struct BODY's identity for the slot join: FNV-1a-64 of its text with every whitespace byte dropped, in hex. Two files
// whose bodies of one tag read the same are one type; bodies that differ are two (valuerefindex.h SlotIndex::addFact).
inline std::string vrBodyDigest( std::string_view body )
{
    std::uint64_t h = 14695981039346656037ull;
    for( const char c : body )
    {
        if( c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\f' && c != '\v' )
        {
            h = hashutil::fnv1aAbsorb( h, c );
        }
    }
    std::string hex( 16, '0' );
    for( std::size_t i = 16; i > 0; --i, h >>= 4 )
    {
        hex[i - 1] = "0123456789abcdef"[ h & 0xF ];
    }
    return hex;
}

// A written slot or callee, made attribute-safe: whitespace runs collapse to one space (an XML attribute may not
// carry a raw newline) and the text is capped. Escaping is the emitter's job. The cut is serialize.h
// truncateUtf8WithEllipsis's (that header is not reachable from the ingest side): "…" only when text was really cut —
// a text of exactly kVrTextCap bytes is whole — and never inside a UTF-8 sequence (a lead byte without its
// continuation bytes would reach into=/through= as an invalid character).
// VALUE-PRESERVING OPERATORS (L4, train 28): a binary operator whose RESULT is one of its operands, so a function named
// there lands in the slot the whole expression fills — `this.getPath = options.getPath ?? getPath` stores getPath.
// One shared walk (transparent() below) reads this table, per family, as data:
//   * leftLands: the LEFT operand can be the result. `f || g`, `f ?? g`, `f or g` yield f (a function is truthy and
//     never nullish); `f && g`, `f and g` yield g, never f — a function on the left of && only decides, so it is no row.
//   * the right operand always can.
// Families with no row here, and why: C/C++ and Go `||` / `&&` yield a truth value (int or bool), never an operand, so
// a function there is a test, not a stored value. The conditional `c ? f : g` (C, C++, JS/TS; Python `f if c else g`)
// and parentheses are handled by transparent() for every family already. Value references are captured for the C, JS,
// Python and Go families only (model.h kValueRefFamilyOfLang); Ruby, Java, C#, Swift, Rust, Bash have no
// value-reference capture at all, so they have no operator to walk either. (Ruby `a || m` needs none: a bare `m` is a
// call there and is already an edge; Ruby's function value is `method(:m)`, a different shape.)
struct VrPassOp
{
    VrFam            fam;
    std::string_view nodeKind;
    std::string_view op;
    bool             leftLands;
};
inline constexpr VrPassOp kVrPassOps[] = {
    { VrFam::Js, "binary_expression", "??", true },
    { VrFam::Js, "binary_expression", "||", true },
    { VrFam::Js, "binary_expression", "&&", false },
    { VrFam::Py, "boolean_operator",  "or", true },
    { VrFam::Py, "boolean_operator",  "and", false },
};
// The JS logical ASSIGNMENTS (`x ??= f`, `x ||= f`, `x &&= f`) store the right operand into the left exactly as `=`
// may: classify() reads them as an assignment. No other family has a value-preserving compound assignment
// (C `x |= f` and Python `x |= f` are bitwise/set operators whose result is not f).
inline constexpr std::string_view kVrJsLogicalAssignOps[] = { "\?\?=", "||=", "&&=" };   // escaped: unescaped, those three characters spell a trigraph

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

// IX-3 name-template dispatch: the dynamic-lookup FORMS per value-ref family, as data (one row per form; no Lang compare in
// the walk). A Python row names a callee (`getattr( o, NAME )`, nameArg = the NAME position) or, dictGet, the attribute
// `X.__dict__.get( NAME )` (callee = "__dict__"); a computedMember row arms `o[ NAME ]` (JS/TS). Ruby send/public_send and
// PHP `$o->{…}` are not armed: neither language has a value-ref family yet (model.h kValueRefFamilyOfLang).
struct VrPatternLookup
{
    VrFam            fam;
    std::string_view callee;
    std::uint8_t     nameArg        = 0;
    bool             dictGet        = false;
    bool             computedMember = false;
    bool             testOnly       = false;   // a capability test (hasattr): the name is looked up for its presence, never to call it
};
inline constexpr VrPatternLookup kVrPatternLookups[] = {
    { VrFam::Py, "getattr", 1, false, false, false },
    { VrFam::Py, "hasattr", 1, false, false, true },
    { VrFam::Py, "__dict__", 0, true, false, false },
    { VrFam::Js, "", 0, false, true, false },
};
// IX-1 SLOT-TYPE JOIN: which field calls are calls through a stored function, per language, as data: model.h kVrSlotLangs (shared
// with the join). C has no member functions, so EVERY field call `x->f( … )` calls through a function-pointer field (or a macro
// the grammar reads as one). A C++ field call is mostly a member-function call: there the receiver must be declared with the
// `struct` / `union` keyword, or be declared with a struct type whose body in this same file declares the callee as a
// function-pointer field. Go (callSide MemberCallByName): this walk records only the STORE side (a keyed composite-literal field, a field
// assignment, a parameter stored into one); the call side is the ordinary member call, joined by field name in valuerefindex.h.

// A template's literal side must hold this many identifier characters to be matched (`f"_{m}"` is too wide).
inline constexpr std::size_t kVrPatternMinLiteral = 3;

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

// A name a scope declares with a struct type (IX-1): the type's key and whether the `struct` / `union` keyword wrote it.
struct VrTyped
{
    std::string_view name;
    std::string      type;
    bool             structKw = false;
};

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
    std::vector<VrTyped>          types;           // IX-1: the names declared here with a struct type (C family)
};

// IX-1: one initializer POSITION of a struct body: the field's name ("" = an anonymous struct / union member, which holds one
// position but no call names it) and whether a non-braced value there would be brace-elided into it (an array, or a field of
// a struct type this file knows), which makes every later index unprovable.
struct VrSlotField
{
    std::string_view name;
    bool             aggregate = false;
    bool             array     = false;   // an array field: a string literal fills it as ONE value (no elision)
    bool             unseen    = false;   // typed by a name this file declares no struct body or scalar typedef for (a header's
                                          // struct typedef may hide here): a non-braced value at it makes every LATER index unprovable
};
// IX-1: one struct body of this file, its initializer positions in declaration order (a positional initializer's index →
// field). A position at or past `exactUpTo` is unprovable (a base class comes first, an #if'd field before it).
struct VrStructFields
{
    std::string              key;
    std::vector<VrSlotField> fields;
    std::size_t              exactUpTo = static_cast<std::size_t>( -1 );
};

// IX-1: this file's typedef / using aliases of struct types, in order (alias → struct type key).
struct VrAliases
{
    std::vector<std::pair<std::string, std::string>> pairs;
    // A struct type key through the aliases (a short chain, cut; never a cycle).
    std::string_view resolve( std::string_view key ) const
    {
        for( int hop = 0; hop < 4; ++hop )
        {
            const auto it = std::ranges::find( pairs, key, []( const auto& a ) { return std::string_view( a.first ); } );
            if( it == pairs.end() )
            {
                break;
            }
            key = it->second;
        }
        return key;
    }
};

// IX-1: this file's typedefs of SCALAR types — a pointer or function pointer (`typedef struct x *xp;`, `typedef void ( *fp )(
// int );`: never an aggregate, even when it points at one) or a plain name over a scalar base. An array is none. A field typed
// by a name neither this list nor the file's struct bodies hold may be another file's struct (VrSlotField::unseen).
struct VrScalarTypedefs
{
    std::vector<std::string_view> names;
    // A type no value is brace-elided into: a primitive / enum, or a typedef this file declares as one.
    bool scalar( TSNode ty, std::string_view src ) const
    {
        const char* t = ts_node_is_null( ty ) ? "" : ts_node_type( ty );
        return kindIs( t, "primitive_type" ) || kindIs( t, "sized_type_specifier" ) || kindIs( t, "enum_specifier" )
            || ( kindIs( t, "type_identifier" ) && std::ranges::contains( names, nodeTextOf( ty, src ) ) );
    }
    // Typedef declarator `d` (scalarBase: the typedef's type is scalar): its name when it declares a scalar type.
    void note( TSNode d, bool scalarBase, TSFieldId fDeclarator, std::string_view src )
    {
        bool indirect = false;
        for( int depth = 0; depth < 16 && !ts_node_is_null( d ); ++depth )
        {
            const char* dt = ts_node_type( d );
            if( kindIs( dt, "type_identifier" ) )
            {
                if( indirect || scalarBase )
                {
                    names.push_back( nodeTextOf( d, src ) );
                }
                return;
            }
            if( kindIs( dt, "array_declarator" ) )
            {
                return;
            }
            indirect = indirect || kindIs( dt, "pointer_declarator" ) || kindIs( dt, "function_declarator" );
            const TSNode inner = ts_node_child_by_field_id( d, fDeclarator );
            d = ts_node_is_null( inner ) ? ts_node_named_child( d, 0 ) : inner;
        }
    }
};

// IX-1: how a field's declared type takes a non-braced initializer value (`field_identifier` declarators only — a pointer or
// array declarator decides itself): { a struct type this file holds a body for (`known`), a NAMED type this file holds neither
// a body nor a scalar typedef for (VrSlotField::unseen) }.
inline std::pair<bool, bool> vrFieldTypeClass( TSNode ftNode, bool known, const VrScalarTypedefs& scalars, std::string_view src )
{
    const char* t       = ts_node_is_null( ftNode ) ? "" : ts_node_type( ftNode );
    const bool  structT = kindIs( t, "struct_specifier" ) || kindIs( t, "union_specifier" ) || ( kindIs( t, "type_identifier" ) && known );
    const bool  named   = kindIs( t, "type_identifier" ) || kindIs( t, "qualified_identifier" ) || kindIs( t, "template_type" )
                       || kindIs( t, "macro_type_specifier" );   // `TAILQ_ENTRY( x ) e;`: a macro's expansion has an unknown width
    return { structT, !structT && named && !scalars.scalar( ftNode, src ) };
}

// IX-1: an anonymous struct / union MEMBER (`union { … };` in a body: no declarator, an untagged specifier) — one position.
inline bool vrAnonymousMember( TSNode k, TSNode ftNode, TSFieldId fDeclarator, TSFieldId fName ) noexcept
{
    return fDeclarator != 0 && fName != 0 && ts_node_is_null( ts_node_child_by_field_id( k, fDeclarator ) ) && !ts_node_is_null( ftNode )
        && ( kindIs( ts_node_type( ftNode ), "struct_specifier" ) || kindIs( ts_node_type( ftNode ), "union_specifier" ) )
        && ts_node_is_null( ts_node_child_by_field_id( ftNode, fName ) );
}

// IX-1: the callee of `( *x->f )( … )` is x->f (the explicit dereference of the same function-pointer field); else `f` itself.
inline TSNode vrDerefCallee( TSNode f, TSFieldId fArgument ) noexcept
{
    if( fArgument == 0 || ts_node_is_null( f ) || !kindIs( ts_node_type( f ), "parenthesized_expression" ) )
    {
        return f;
    }
    const TSNode inner = ts_node_named_child( f, 0 );
    if( !ts_node_is_null( inner ) && kindIs( ts_node_type( inner ), "pointer_expression" ) && ts_node_child_count( inner ) > 0
        && kindIs( ts_node_type( ts_node_child( inner, 0 ) ), "*" ) )
    {
        return ts_node_child_by_field_id( inner, fArgument );
    }
    return f;
}

// A field declaration carrying the `static` storage class (C++ static data member).
inline bool vrStaticMember( TSNode k, std::string_view src )
{
    bool found = false;
    ChildCursor c( k );
    forEachNamedChild( k, c.cur, [ & ]( TSNode x )
    {
        found = found || ( kindIs( ts_node_type( x ), "storage_class_specifier" ) && nodeTextOf( x, src ) == "static" );
        return !found;
    } );
    return found;
}

// The single field a designator list names (`.f = …` → "f"); "" for a nested (`.a.b`), array (`[i]`) or missing designator.
inline std::string_view vrDesignatedField( TSNode pair, TSFieldId fDesignator, std::string_view src )
{
    std::string_view out;
    int              n = 0;
    ChildCursor      c( pair );
    ts_tree_cursor_reset( &c.cur, pair );
    if( ts_tree_cursor_goto_first_child( &c.cur ) )
    {
        do
        {
            const TSNode x = ts_tree_cursor_current_node( &c.cur );
            if( ts_tree_cursor_current_field_id( &c.cur ) == fDesignator
                || ( n == 0 && ts_node_is_named( x ) && kindIs( ts_node_type( x ), "field_identifier" ) ) )
            {
                ++n;
                const char* xt = ts_node_type( x );
                out = kindIs( xt, "field_designator" ) ? nodeTextOf( ts_node_named_child( x, 0 ), src )
                    : kindIs( xt, "field_identifier" ) ? nodeTextOf( x, src )
                                                       : std::string_view();
            }
        }
        while( ts_tree_cursor_goto_next_sibling( &c.cur ) );
    }
    return n == 1 ? out : std::string_view();
}

// The initializer position of `value`, a direct child of struct literal `list`, exactly — C's rule: positions count from 0,
// and a designator `.f = …` moves the next one to f's position + 1. -1 when the index is not provable: a nested or array
// designator, a field no position names, brace elision (a non-braced value at an aggregate field), past exactUpTo, a preprocessor
// conditional in the list (the entry and everything after it depend on the build).
inline std::ptrdiff_t vrPositionOf( TSNode list, TSNode value, const VrStructFields& sf, TSFieldId fDesignator, std::string_view src )
{
    std::size_t         pos = 0;
    const std::uint32_t cnt = ts_node_named_child_count( list );
    for( std::uint32_t i = 0; i < cnt; ++i )
    {
        const TSNode k = ts_node_named_child( list, i );
        const char* kt = ts_node_type( k );
        if( std::string_view( kt ).starts_with( "preproc_" ) )
        {
            return -1;   // an #if / #ifdef inside the literal: this entry and every later position depend on the build (noteStructBody's exactUpTo, literal side)
        }
        if( ts_node_is_extra( k ) )
        {
            if( kindIs( kt, "comment" ) )
            {
                continue;
            }
            return -1;   // any other extra (the grammar may read a `#ifdef` line as one): a position the text does not show
        }
        if( kindIs( kt, "initializer_pair" ) )
        {
            const std::string_view f  = vrDesignatedField( k, fDesignator, src );
            const auto             at = std::ranges::find( sf.fields, f, &VrSlotField::name );
            if( f.empty() || at == sf.fields.end() )
            {
                return -1;
            }
            pos = static_cast<std::size_t>( at - sf.fields.begin() ) + 1;
            continue;
        }
        if( pos >= sf.fields.size() || pos >= sf.exactUpTo )
        {
            return -1;
        }
        const VrSlotField& fld = sf.fields[pos];
        const bool         braced = kindIs( kt, "initializer_list" )
                                 || ( fld.array && ( kindIs( kt, "string_literal" ) || kindIs( kt, "concatenated_string" ) ) );
        if( fld.aggregate && !braced )
        {
            return -1;   // brace elision: this value fills the aggregate's first member, and the positions after it shift
        }
        if( ts_node_eq( k, value ) )
        {
            return fld.name.empty() ? -1 : static_cast<std::ptrdiff_t>( pos );
        }
        if( fld.unseen && !braced )
        {
            return -1;   // the field's type may be another file's struct: this value may be brace-elided into it, shifting the rest
        }
        ++pos;
    }
    return -1;
}

// The walk's DISCLOSE sink for the depth cap: the subtrees kVrMaxDepth stopped it above, and the first one's site.
struct VrDepthCut
{
    enum class DisclosureWhy : std::uint8_t
    {
        SubtreesBelowMaxDepth,   // nodes past kVrMaxDepth were not visited: their value references are not captured
    };
    std::uint32_t subtrees  = 0;
    std::uint32_t startByte = 0;
    std::uint32_t line      = 0;
    bool          disclosed = false;
    void disclose( DisclosureWhy ) noexcept
    {
        disclosed = true;
    }
};
// A node at kVrMaxDepth whose children a value walk does not visit: a value reference below it is never captured. The
// first one's site is kept as the clue the answers print (value_refs_depth_at=).
inline void noteVrDepthCut( VrDepthCut& cut, TSNode n ) noexcept
{
    if( cut.subtrees == 0 )
    {
        cut.startByte = ts_node_start_byte( n );
        cut.line      = ts_node_start_point( n ).row + 1;
    }
    if( cut.subtrees < UINT32_MAX )
    {
        ++cut.subtrees;
    }
}
// The file's ONE depth-cut record (RECORD SHAPE in the header comment): the cut is disclosed through it on the answers that
// read value references (valuerefs.h value_refs_depth_capped=, --dead-code; the named exceptions are in the header comment),
// and it is cached with the file's other references, so a warm run discloses it too.
inline RawRef vrDepthCutRecord( std::uint32_t fileId, Lang lang, VrDepthCut& cut )
{
    EXPECTS( cut.subtrees > 0, "a depth-cut record is written only when the cap stopped the walk" );
    DISCLOSE( cut, VrDepthCut::DisclosureWhy::SubtreesBelowMaxDepth,
              "value references: subtrees below kVrMaxDepth were not visited (value_refs_depth_capped=)" );
    RawRef r;
    r.fileId        = fileId;
    r.startByte     = cut.startByte;
    r.line          = cut.line;
    r.lang          = lang;
    r.role          = RefRole::Value;
    r.qualifier     = std::string( 1, kValueRefDepthCutScope );   // name stays "": no identifier is empty
    r.argCount      = static_cast<std::uint16_t>( std::min<std::uint32_t>( cut.subtrees, 0xFFFFu ) );
    r.argCountKnown = true;
    return r;
}

struct VrAnc
{
    TSNode        node {};
    const char*   kind = "";
    TSFieldId     field = 0;          // the field this node occupies in its parent (0 = none)
    std::uint32_t namedIndex = 0;     // index among the parent's named, non-extra children
    std::uint32_t childNamed = 0;     // running count of this node's named, non-extra children entered so far
    bool          opensScope = false;
};

// ── FN-SLOT S2 fix 1: where a C++ class is defined and a `&Cls::m` is written (model.h VrMemberScope) ───────────────────────
// One scope segment as a qualifier writes it: a template-id `W<int>` is W.
inline std::string_view vrScopeSegment( TSNode seg, std::string_view src ) noexcept
{
    if( !ts_node_is_null( seg ) && kindIs( ts_node_type( seg ), "template_type" ) )
    {
        seg = fieldChild( seg, NodeField::Name );
    }
    return ts_node_is_null( seg ) ? std::string_view() : nodeTextOf( seg, src );
}
inline void vrAppendScope( std::string& path, std::string_view seg )
{
    if( !seg.empty() )
    {
        path += path.empty() ? "" : "::";
        path += seg;
    }
}
// `inline namespace v1 { … }`: the keyword is the namespace_definition's first, anonymous child. Qualifiers need not write it.
inline bool vrInlineNamespace( TSNode ns, std::string_view src ) noexcept
{
    const TSNode first = ts_node_child( ns, 0 );
    return !ts_node_is_null( first ) && !ts_node_is_named( first ) && nodeTextOf( first, src ) == "inline";
}
// The scope an out-of-line definition's declarator writes (`int a::C::f() { … }` is inside a::C), appended to `path`.
inline void vrDeclaratorScope( TSNode fn, std::string_view src, std::string& path )
{
    TSNode d = fieldChild( fn, NodeField::Declarator );
    for( int guard = 0; guard < 8 && !ts_node_is_null( d ) && !kindIs( ts_node_type( d ), "qualified_identifier" ); ++guard )
    {
        d = fieldChild( d, NodeField::Declarator );   // pointer / reference / function declarator
    }
    for( int guard = 0; guard < 8 && !ts_node_is_null( d ) && kindIs( ts_node_type( d ), "qualified_identifier" ); ++guard )
    {
        vrAppendScope( path, vrScopeSegment( fieldChild( d, NodeField::Scope ), src ) );
        d = fieldChild( d, NodeField::Name );
    }
}
// The named namespaces and classes enclosing anc[0..end) outermost first, "::"-joined (an anonymous or inline namespace is
// transparent), then the scope of an out-of-line function definition among them.
inline std::string vrEnclosingScopePath( std::span<const VrAnc> anc, std::size_t end, std::string_view src )
{
    std::string path;
    for( const VrAnc& a : anc.first( end ) )
    {
        if( kindIs( a.kind, "namespace_definition" ) )
        {
            if( !vrInlineNamespace( a.node, src ) )
            {
                const TSNode nm = fieldChild( a.node, NodeField::Name );
                vrAppendScope( path, ts_node_is_null( nm ) ? std::string_view() : nodeTextOf( nm, src ) );
            }
        }
        else if( kindIs( a.kind, "class_specifier" ) || kindIs( a.kind, "struct_specifier" ) || kindIs( a.kind, "union_specifier" ) )
        {
            vrAppendScope( path, vrScopeSegment( fieldChild( a.node, NodeField::Name ), src ) );
        }
        else if( kindIs( a.kind, "function_definition" ) )
        {
            vrDeclaratorScope( a.node, src, path );
        }
    }
    return path;
}
// This file's `using ns::Cls;` declarations and `using namespace ns;` directives so far (anywhere in the file: a floor in the
// declining direction only — a qualifier that is not the class's own scope declines, never binds).
struct VrUsings
{
    std::vector<std::pair<std::string, std::string>> declared;     // (Cls, the qualifier `ns` written before it)
    std::vector<std::string>                         directives;   // `ns` of each `using namespace ns;`

    // `n` is a using_declaration: `using namespace ns;` (the anonymous `namespace` token is its second child) or `using ns::Cls;`.
    void note( TSNode n, std::string_view src )
    {
        const TSNode target = ts_node_named_child( n, 0 );
        if( ts_node_is_null( target ) )
        {
            return;
        }
        const TSNode           second = ts_node_child( n, 1 );
        const std::string_view full   = nodeTextOf( target, src );
        if( !ts_node_is_named( second ) && nodeTextOf( second, src ) == "namespace" )
        {
            directives.emplace_back( full );
            return;
        }
        if( const std::size_t cut = full.rfind( "::" ); cut != std::string_view::npos )
        {
            declared.emplace_back( std::string( full.substr( cut + 2 ) ), std::string( full.substr( 0, cut ) ) );
        }
    }
    // The qualifier a `using` of class `owner` writes ("" when none).
    std::string_view qualifierOf( std::string_view owner ) const noexcept
    {
        for( const auto& [ cls, qualifier ] : declared )
        {
            if( cls == owner )
            {
                return qualifier;
            }
        }
        return {};
    }
    std::string directivesJoined() const
    {
        std::string out;
        for( const std::string& d : directives )
        {
            out += out.empty() ? "" : ",";
            out += d;
        }
        return out;
    }
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
        m_fArguments   = fieldIdFor( tl, NodeField::Arguments );
        m_fSource      = ts_language_field_id_for_name( tl, "source", 6 );
        m_fReceiver    = ts_language_field_id_for_name( tl, "receiver", 8 );
        m_fScope       = ts_language_field_id_for_name( tl, "scope", 5 );
        const VrSlotLang* slotRow = vrSlotLang( m_lang );
        m_slot         = slotRow != nullptr && slotRow->callSide == VrSlotCallSide::ThroughRows ? slotRow : nullptr;
        m_slotByName   = slotRow != nullptr && slotRow->callSide == VrSlotCallSide::MemberCallByName;
        m_fwd          = callForwardersOf( m_lang );
        m_fwdArmed     = !m_fwd.empty();
        const RegLang* regRow = regLang( m_lang );   // REGISTRAR: a language whose registrars store a parameter into a container
        m_regStores    = regRow != nullptr && regRow->form == RegForm::ReceiverMethod ? regRow->containerStores : std::span<const std::string_view>{};

        VrScope file;
        file.node = root;
        m_scopes.push_back( std::move( file ) );

        ChildCursor  walker( root );   // RAII: the walk's one cursor, released on every exit (hazardpatterncheck E)
        TSTreeCursor& cur = walker.cur;
        enter( root, 0 );
        for( ;; )
        {
            if( m_anc.size() < kVrMaxDepth )
            {
                if( ts_tree_cursor_goto_first_child( &cur ) )
                {
                    enter( ts_tree_cursor_current_node( &cur ), ts_tree_cursor_current_field_id( &cur ) );
                    continue;
                }
            }
            else if( ts_node_child_count( m_anc.back().node ) > 0 )
            {
                noteVrDepthCut( m_depthCut, m_anc.back().node );   // the cap stops the walk ABOVE these children: one subtree not visited
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
        emitForwardedCalls();
        if( m_depthCut.subtrees > 0 )
        {
            m_out.push_back( vrDepthCutRecord( m_fileId, m_lang, m_depthCut ) );
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
            case VrFam::Rust:   // never: Rust runs ingest_rustslots.h, not this walk
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
            case VrFam::Rust:   // never: Rust runs ingest_rustslots.h, not this walk
            case VrFam::None: break;
        }
    }

    // `defaulted` (optional): one flag per returned name, true for a parameter written with a default value.
    std::vector<std::string_view> pyParamNames( TSNode params, std::vector<bool>* defaulted = nullptr ) const
    {
        std::vector<std::string_view> names;
        ChildCursor c( params );
        forEachNamedChild( params, c.cur, [ & ]( TSNode k )
        {
            const char*       t      = ts_node_type( k );
            const std::size_t before = names.size();
            bool              dflt   = false;
            if( kindIs( t, "identifier" ) )
            {
                names.push_back( text( k ) );
            }
            else if( kindIs( t, "default_parameter" ) || kindIs( t, "typed_default_parameter" ) )
            {
                names.push_back( text( child( k, m_fName ) ) );
                dflt = true;
            }
            else if( kindIs( t, "typed_parameter" ) || kindIs( t, "list_splat_pattern" ) || kindIs( t, "dictionary_splat_pattern" ) )
            {
                const TSNode id = ts_node_named_child( k, 0 );
                names.push_back( !ts_node_is_null( id ) && kindIs( ts_node_type( id ), "identifier" ) ? text( id ) : std::string_view() );
            }
            if( defaulted != nullptr && names.size() > before )
            {
                defaulted->push_back( dflt );
            }
            return true;
        } );
        return names;
    }

    // Python: parameter `name` of function node `fn` is written with a default value (`x=1`, `x: int = 1`).
    bool pyParamHasDefault( TSNode fn, std::string_view name ) const
    {
        const TSNode params = child( fn, m_fParameters );
        if( ts_node_is_null( params ) )
        {
            return false;
        }
        std::vector<bool> defaulted;
        const auto        names = pyParamNames( params, &defaulted );
        const auto        at    = std::ranges::find( names, name );
        return at != names.end() && defaulted[ static_cast<std::size_t>( at - names.begin() ) ];
    }

    // Python: is store target `n` rooted at `self` (`self.x`, `self.x[ k ]`, `self.x.y[ k ]`)?
    bool pySelfRooted( TSNode n ) const
    {
        for( int guard = 0; guard < 16 && !ts_node_is_null( n ); ++guard )
        {
            if( kindIs( ts_node_type( n ), "identifier" ) )
            {
                return text( n ) == "self";
            }
            if( kindIs( ts_node_type( n ), "attribute" ) )
            {
                n = child( n, m_fObject );
            }
            else if( kindIs( ts_node_type( n ), "subscript" ) )
            {
                n = child( n, m_fValue );
            }
            else
            {
                return false;
            }
        }
        return false;
    }

    // Python: identifier `id` is the KEY of a subscript store into `self` (`self.d[ id ] = handler`): it is read only to say where the
    // value goes, never stored itself.
    bool pyStoreKey( TSNode id ) const
    {
        const TSNode sub = ts_node_parent( id );
        if( ts_node_is_null( sub ) || !kindIs( ts_node_type( sub ), "subscript" ) || !ts_node_eq( child( sub, m_fSubscript ), id ) )
        {
            return false;
        }
        const TSNode as = ts_node_parent( sub );
        return !ts_node_is_null( as ) && kindIs( ts_node_type( as ), "assignment" ) && ts_node_eq( child( as, m_fLeft ), sub )
            && pySelfRooted( sub );
    }

    // Python: is identifier `id` only a label (an attribute name or a keyword-argument name), never a read of a variable?
    bool pyLabel( TSNode id ) const
    {
        const TSNode parent = ts_node_parent( id );
        return !ts_node_is_null( parent )
            && ( ( kindIs( ts_node_type( parent ), "attribute" ) && ts_node_eq( child( parent, m_fAttribute ), id ) )
                 || ( kindIs( ts_node_type( parent ), "keyword_argument" ) && ts_node_eq( child( parent, m_fName ), id ) ) );
    }

    // Python: does the subtree `n` read identifier `name`? A subtree too large to scan answers false (the caller then refuses).
    bool pyReads( TSNode n, std::string_view name ) const
    {
        constexpr std::size_t kScanCap = 512;
        std::vector<TSNode>   stack{ n };
        for( std::size_t seen = 0; !stack.empty() && seen <= kScanCap; ++seen )
        {
            const TSNode cur = stack.back();
            stack.pop_back();
            if( kindIs( ts_node_type( cur ), "identifier" ) )
            {
                if( text( cur ) == name && !pyLabel( cur ) )
                {
                    return true;
                }
                continue;
            }
            for( std::uint32_t k = 0, cc = ts_node_named_child_count( cur ); k < cc; ++k )
            {
                stack.push_back( ts_node_named_child( cur, k ) );
            }
        }
        return false;
    }

    // Python: is `ch`, a child of `node`, what `node` stores into `self` — the arguments of `self.<field>.<store>( … )` or the right side of
    // a store into `self` — in a store that does not also hold `keep`?
    bool pyStoredChild( TSNode node, TSNode ch, std::string_view keep ) const
    {
        const char* kind = ts_node_type( node );
        bool        into = false;
        if( kindIs( kind, "call" ) )
        {
            const TSNode fn = child( node, m_fFunction );
            into = kindIs( ts_node_type( ch ), "argument_list" ) && !ts_node_is_null( fn ) && kindIs( ts_node_type( fn ), "attribute" )
                && std::ranges::find( m_regStores, text( child( fn, m_fAttribute ) ) ) != m_regStores.end()
                && !selfField( child( fn, m_fObject ) ).empty();
        }
        else if( kindIs( kind, "assignment" ) )
        {
            into = ts_node_eq( ch, child( node, m_fRight ) ) && pySelfRooted( child( node, m_fLeft ) );
        }
        return into && !pyReads( ch, keep );
    }

    // Python: is identifier `id` a use of one of the `others` that the allowlist refuses (see pyOtherParamUsed)? `stored`: it sits inside a
    // store into `self` that does not hold the registered value.
    bool pyOtherHit( TSNode id, bool stored, const std::vector<std::pair<std::string_view, bool>>& others ) const
    {
        const auto hit = std::ranges::find( others, text( id ), &std::pair<std::string_view, bool>::first );
        return hit != others.end() && !pyLabel( id ) && ( hit->second ? stored : !pyStoreKey( id ) );
    }

    // Python: is the one parameter a store shows (`keep`) provably the registered value? An ALLOWLIST over the method's other parameters
    // (after `self`), refused as soon as one is not provably beside the point:
    //   a parameter written WITHOUT a default is allowed only as the subscript key of the `self` store itself (`self.d[ name ] = handler`);
    //     any other use of it (a condition, a call, a second store) refuses, because the receiver may be that one;
    //   a parameter written WITH a default (`sender=None`, `weak=True`) is allowed anywhere EXCEPT inside a store into `self` that does not
    //     also hold `keep` (the arguments of `self.<field>.<store>( … )`, the right side of `self.x = …` / `self.x[ k ] = …`): a second,
    //     separate stored candidate (`self.rx.append( wrap( fn ) )` beside `self.fl.append( ev )`) makes the receiver unprovable, while
    //     `self.rx.append( ( receiver, sender ) )` stores the option beside the value, as Django's `Signal.connect` does.
    // An attribute or keyword name is no use. A body too large to scan counts as a use.
    bool pyOtherParamUsed( TSNode fn, std::string_view keep ) const
    {
        const TSNode params = child( fn, m_fParameters );
        const TSNode body   = fieldChild( fn, NodeField::Body );
        if( ts_node_is_null( params ) || ts_node_is_null( body ) )
        {
            return false;
        }
        std::vector<bool> defaulted;
        const auto        names = pyParamNames( params, &defaulted );
        std::vector<std::pair<std::string_view, bool>> others;   // name, written with a default
        for( std::size_t k = 1; k < names.size(); ++k )          // names[0] is self
        {
            if( !names[k].empty() && names[k] != keep )
            {
                others.emplace_back( names[k], static_cast<bool>( defaulted[k] ) );
            }
        }
        if( others.empty() )
        {
            return false;
        }
        constexpr std::size_t kScanCap = 4096;
        struct Item { TSNode node; bool stored; };
        std::vector<Item> stack{ { body, false } };
        for( std::size_t seen = 0; !stack.empty(); ++seen )
        {
            if( seen > kScanCap )
            {
                return true;
            }
            const Item cur = stack.back();
            stack.pop_back();
            if( kindIs( ts_node_type( cur.node ), "identifier" ) )
            {
                if( pyOtherHit( cur.node, cur.stored, others ) )
                {
                    return true;
                }
                continue;
            }
            for( std::uint32_t k = 0, cc = ts_node_named_child_count( cur.node ); k < cc; ++k )
            {
                const TSNode ch = ts_node_named_child( cur.node, k );
                stack.push_back( { ch, cur.stored || pyStoredChild( cur.node, ch, keep ) } );
            }
        }
        return false;
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
            case VrFam::Rust:   // never: Rust runs ingest_rustslots.h, not this walk
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

    // A C declarator wrapper between a parameter list and the node that owns the declarator chain.
    static constexpr std::string_view kDeclaratorWrappers[] = {
        "function_declarator", "abstract_function_declarator", "pointer_declarator", "abstract_pointer_declarator",
        "reference_declarator", "abstract_reference_declarator", "parenthesized_declarator",
        "abstract_parenthesized_declarator", "attributed_declarator", "array_declarator", "abstract_array_declarator",
    };
    static bool isDeclaratorWrapper( const char* t ) noexcept
    {
        return std::ranges::find( kDeclaratorWrappers, std::string_view( t ) ) != std::ranges::end( kDeclaratorWrappers );
    }

    // Is node kind `t` (about to be entered; its parent is m_anc.back()) a parameter list, or a parameter of one, that
    // belongs to no function this walk has opened? A parameter declares its name only inside the function that OWNS the
    // list — the innermost scope, a function, whose own declarator / `parameters` holds it. A prototype (`void
    // set_handler( void (*handler)( int ) );`), a function-pointer typedef or parameter (`typedef void (*fn_t)( int sig
    // );`), a C++ member declaration, a Go func type or interface method (`type H func( w Writer )`) and a TS function type,
    // signature or `declare function` open no scope, so their names used to land in the ENCLOSING scope — the file scope
    // at top level — and hid every same-named function there (`signal( SIGINT, handler )` lost its row). Python has no
    // bodiless signature. A C parameter list NOT under a function declarator (a C++ catch clause, a template parameter
    // list) keeps declaring into the innermost scope, as before.
    bool foreignParameters( const char* t ) const noexcept
    {
        if( m_anc.size() < 2 )
        {
            return false;
        }
        const VrScope& s      = m_scopes.back();
        const VrAnc&   parent = m_anc.back();
        switch( m_fam )
        {
            case VrFam::C:
            {
                if( !( kindIs( t, "parameter_declaration" ) || kindIs( t, "optional_parameter_declaration" ) ) || !kindIs( parent.kind, "parameter_list" ) )
                {
                    return false;
                }
                std::size_t j = m_anc.size() - 2;
                if( !kindIs( m_anc[j].kind, "function_declarator" ) && !kindIs( m_anc[j].kind, "abstract_function_declarator" ) )
                {
                    return false;   // a catch clause, a template parameter list: unchanged
                }
                while( j > 0 && isDeclaratorWrapper( m_anc[j].kind ) )
                {
                    --j;
                }
                return !( s.isFunction && ts_node_eq( m_anc[j].node, s.node ) );
            }
            case VrFam::Go:
            {
                if( !( kindIs( t, "parameter_declaration" ) || kindIs( t, "variadic_parameter_declaration" ) ) || !kindIs( parent.kind, "parameter_list" ) )
                {
                    return false;
                }
                return !( s.isFunction && ts_node_eq( m_anc[ m_anc.size() - 2 ].node, s.node ) );   // receiver, parameters and named results
            }
            case VrFam::Js:
            {
                return kindIs( t, "formal_parameters" ) && !( s.isFunction && ts_node_eq( parent.node, s.node ) );
            }
            case VrFam::Py:
            case VrFam::Rust:   // never: Rust runs ingest_rustslots.h, not this walk
            case VrFam::None: break;
        }
        return false;
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
        if( !foreignParameters( a.kind ) )
        {
            harvest( n, a.kind, m_scopes.back().decls );
            noteSlotTypes( n, a.kind );   // IX-1: the declared struct types, beside the names (inert without a slot row)
        }
        noteStructBody( n, a.kind );      // IX-1: a struct body's field order and facts (m_anc.back() is the parent)
        noteUsing( n, a.kind );           // FN-SLOT S2 fix 1: where a bare `&Cls::m` may name an external class (m_anc.back() is the parent)
        if( m_fwdArmed )
        {
            noteForwardProof( n, a.kind );
        }
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
        else if( memberValueKind( a.kind ) )
        {
            memberValueAt( i );
        }
        else if( isCallKind( a.kind ) )
        {
            slotThroughAt( n );   // IX-1 (inert without a slot row)
            throughAt( n );
            patternAtCall( n );
        }
        else if( m_fam == VrFam::Js && kindIs( a.kind, "subscript_expression" ) )
        {
            patternAtSubscript( n );
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

    // ── call forwarders (model.h kCallForwarders) ───────────────────────────────────────────────────────
    // Is the string node `str` a module specifier inside the repository — relative, so it names a file of this tree?
    bool relativeModuleString( TSNode str ) const
    {
        const std::string_view m = vrStringContent( text( str ) );
        return m.starts_with( "./" ) || m.starts_with( "../" );
    }

    // Record what lets a bare name stand for a callable binding, as the walk enters each node (anc = its ancestors, root
    // first): a function declaration at any depth, or a binding of a FILE-SCOPE import from a relative module (a BINDING
    // only — whether it is a function graph.h decides, Reference::forwarded) —
    // `import f from './m'` (anc: program, import_statement, import_clause), `import { g as f } from './m'` (… named_imports),
    // `const f = require( './m' )` / `const { f } = require( './m' )` (anc: program, lexical/variable declaration). A
    // type-only import binds no value; a namespace import binds a module object, never a function.
    void noteForwardProof( TSNode n, const char* t )
    {
        const std::size_t depth = m_anc.size();
        if( kindIs( t, "function_declaration" ) || kindIs( t, "generator_function_declaration" ) )
        {
            const std::string_view nm = text( child( n, m_fName ) );
            if( !nm.empty() )
            {
                m_fnDeclNames.push_back( nm );
            }
        }
        else if( depth == 2 && kindIs( t, "variable_declarator" )
                 && ( kindIs( m_anc[1].kind, "lexical_declaration" ) || kindIs( m_anc[1].kind, "variable_declaration" ) )
                 && requiresRelativeModule( child( n, m_fValue ) ) )
        {
            patternNames( child( n, m_fName ), m_relImportNames );
        }
        else if( depth == 3 && kindIs( t, "identifier" ) && kindIs( m_anc[2].kind, "import_clause" ) && relativeValueImport( m_anc[1] ) )
        {
            m_relImportNames.push_back( text( n ) );
        }
        else if( depth == 4 && kindIs( t, "import_specifier" ) && kindIs( m_anc[3].kind, "named_imports" ) && relativeValueImport( m_anc[1] )
                 && !text( n ).starts_with( "type " ) )
        {
            const TSNode alias = child( n, m_fAlias );
            const std::string_view nm = text( ts_node_is_null( alias ) ? child( n, m_fName ) : alias );
            if( !nm.empty() )
            {
                m_relImportNames.push_back( nm );
            }
        }
    }

    // A file-scope import statement that binds VALUES from a module of this tree.
    bool relativeValueImport( const VrAnc& stmt ) const
    {
        if( !kindIs( stmt.kind, "import_statement" ) )
        {
            return false;
        }
        const std::string_view whole = text( stmt.node );
        return !whole.starts_with( "import type " ) && !whole.starts_with( "import type{" ) && relativeModuleString( child( stmt.node, m_fSource ) );
    }

    // `require( './m' )` with exactly one relative string argument.
    bool requiresRelativeModule( TSNode v ) const
    {
        if( ts_node_is_null( v ) || !kindIs( ts_node_type( v ), "call_expression" ) || text( child( v, m_fFunction ) ) != "require" )
        {
            return false;
        }
        const TSNode args = child( v, m_fArguments );
        if( ts_node_is_null( args ) || ts_node_named_child_count( args ) != 1 )
        {
            return false;
        }
        const TSNode arg = ts_node_named_child( args, 0 );
        return kindIs( ts_node_type( arg ), "string" ) && relativeModuleString( arg );
    }

    // The forwarder row of the member expression `m` (`f.call`, `f.bind`) when its object is a bare identifier.
    const CallForwarder* forwarderOfMember( TSNode m ) const noexcept
    {
        const TSNode obj = child( m, m_fObject );
        if( ts_node_is_null( obj ) || !kindIs( ts_node_type( obj ), "identifier" ) )
        {
            return nullptr;
        }
        return findByField( m_fwd, &CallForwarder::name, text( child( m, m_fProperty ) ) );
    }

    // anc[i] is the identifier `f` of a CALLED member `f.call( … )` / `f.apply( … )` (a Call forwarder): queue the call of
    // f it stands for. The caller has already refused a name some enclosing parameter or local declares; the file-end
    // filter (emitForwardedCalls) keeps the site only when the file declares or imports f; graph.h keeps its call only at a
    // proven Function/Method.
    bool forwardCallAt( std::size_t i, std::string_view name )
    {
        if( i < 2 || !kindIs( m_anc[i].kind, "identifier" ) || m_anc[i].field != m_fObject )
        {
            return false;
        }
        const VrAnc& member = m_anc[i - 1];
        const VrAnc& call   = m_anc[i - 2];
        if( !kindIs( member.kind, "member_expression" ) || !kindIs( call.kind, "call_expression" ) || member.field != m_fFunction )
        {
            return false;
        }
        const CallForwarder* fw = forwarderOfMember( member.node );
        if( fw == nullptr || fw->kind != CallForwardKind::Call )
        {
            return false;
        }
        RawRef r;
        r.fileId    = m_fileId;
        r.startByte = ts_node_start_byte( m_anc[i].node );
        r.line      = ts_node_start_point( m_anc[i].node ).row + 1;
        r.lang      = m_lang;
        r.role      = RefRole::Call;
        r.forwarded = true;   // graph.h keeps it only at a proven Function/Method (an import proves no function)
        r.name      = std::string( name );
        const TSNode args = child( call.node, m_fArguments );
        if( !fw->argsAsArray && !ts_node_is_null( args ) )
        {
            std::uint32_t n      = 0;
            bool          spread = false;
            ChildCursor   c( args );
            forEachNamedChild( args, c.cur, [ & ]( TSNode a )
            {
                if( !ts_node_is_extra( a ) )
                {
                    ++n;
                    spread = spread || kindIs( ts_node_type( a ), "spread_element" );
                }
                return true;
            } );
            r.argCount      = static_cast<std::uint16_t>( std::min<std::uint32_t>( n > 0 ? n - 1 : 0, 0xFFFFu ) );   // the first is the receiver
            r.argCountKnown = !spread;
        }
        m_fwdSites.push_back( std::move( r ) );
        return true;
    }

    // `.bind` (a Value forwarder) is a pass-through: `f.bind( x )` lands f in the slot the whole call fills. Step one is
    // the identifier as the member's object, step two the member as the call's callee.
    bool valueForwardStep( std::size_t i ) const noexcept
    {
        const VrAnc& p = m_anc[i - 1];
        const VrAnc& c = m_anc[i];
        const auto isValueForwarder = [ this ]( TSNode m )
        {
            const CallForwarder* fw = forwarderOfMember( m );
            return fw != nullptr && fw->kind == CallForwardKind::Value;
        };
        if( kindIs( p.kind, "member_expression" ) )
        {
            return i >= 2 && c.field == m_fObject && kindIs( c.kind, "identifier" ) && p.field == m_fFunction
                && kindIs( m_anc[i - 2].kind, "call_expression" ) && isValueForwarder( p.node );
        }
        return kindIs( p.kind, "call_expression" ) && c.field == m_fFunction && kindIs( c.kind, "member_expression" ) && isValueForwarder( c.node );
    }

    // File end: a queued call/apply site becomes a FORWARDED call of f when f is a relative import of the file, or a function
    // the file declares that no file-scope variable of the same name rebinds. Anything else adds nothing (today's answer).
    // An import proves a binding, not a function: graph.h buildGraph keeps the call only at a proven Function/Method.
    void emitForwardedCalls()
    {
        if( m_fwdSites.empty() )
        {
            return;
        }
        const auto sortUnique = []( std::vector<std::string_view>& v )
        {
            std::ranges::sort( v, rw::sortutil::svLess );   // never the default: libstdc++ debug aborts on string_view operator< (portablebuildcheck #6b)
            v.erase( std::ranges::unique( v ).begin(), v.end() );
        };
        sortUnique( m_fnDeclNames );
        sortUnique( m_relImportNames );
        const std::vector<std::string_view>& fileDecls = m_scopes.front().decls;
        for( RawRef& r : m_fwdSites )
        {
            const std::string_view nm = r.name;
            const bool imported = std::ranges::binary_search( m_relImportNames, nm, rw::sortutil::svLess );
            const bool declared = std::ranges::binary_search( m_fnDeclNames, nm, rw::sortutil::svLess ) && std::ranges::find( fileDecls, nm ) == fileDecls.end();
            if( imported || declared )
            {
                m_out.push_back( std::move( r ) );
            }
        }
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
        std::uint32_t litAt = 0;   // REGISTRAR (ProviderRecord): start byte of the object literal this pair is read from, when that
                                   //   literal is proven (providerLiteralDirect) and the value is the pair's value written bare; 0 = none
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
        if( m_fwdArmed && valueForwardStep( i ) )
        {
            return true;
        }
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
        return c.field != 0 && passesOperator( p, c );
    }

    // A value-preserving binary operator (kVrPassOps) whose operand `c` can be the expression's result.
    bool passesOperator( const VrAnc& p, const VrAnc& c ) const noexcept
    {
        for( const VrPassOp& po : kVrPassOps )
        {
            if( po.fam == m_fam && std::string_view( p.kind ) == po.nodeKind && opText( p.node ) == po.op )
            {
                return c.field == m_fRight || ( po.leftLands && c.field == m_fLeft );
            }
        }
        return false;
    }

    bool isLogicalAssignment( TSNode n ) const noexcept
    {
        const std::string_view op = opText( n );
        return m_fam == VrFam::Js && std::ranges::find( kVrJsLogicalAssignOps, op ) != std::ranges::end( kVrJsLogicalAssignOps );
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
                into = "." + vrClean( nm );
                key  = "." + nm;
                return;
            }
            const std::string w( text( ts_node_named_child( k, 0 ) ) );
            into = "[" + vrClean( w ) + "]";   // `[A +\n 1] = f`: an expression, maybe multi-line — written like every other slot
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
            into = "[" + vrClean( w ) + "]";   // the written slot is capped; the match key stays whole (no two keys collide)
            key  = "[" + std::string( w ) + "]";
            return;
        }
        if( m_fam == VrFam::Py )
        {
            into = "[" + vrClean( w ) + "]";   // a non-literal dict key: the value is reached through it, unknowable here
            key  = "*";
            return;
        }
        into = "." + vrClean( w );               // JS property_identifier / Go struct field name, capped as above
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
        if( const std::size_t d = declaringScope( name ); d != 0 )
        {
            paramSlotFact( i, d, name );   // IX1-V2: a parameter stored into a field slot is a fact, never a row
            paramRegFact( i, d, name );    // REGISTRAR: a method parameter stored into a container a field of self holds
            return;   // a parameter or local of that name hides the function
        }
        if( m_fwdArmed && forwardCallAt( i, name ) )
        {
            return;   // `f.call( … )` / `f.apply( … )`: a call of f (decided at file end), never a value use
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
        landValue( i, j, name, s, fileShadow, {} );
    }

    // The classified value `name` at anc[i] (effective position anc[j]): a container it fills is marked fed (its scope's, or
    // the file's), then its Value row. `owner` non-empty: a method value of that receiver type (methodValueAt).
    void landValue( std::size_t i, std::size_t j, std::string_view name, Slot& s, bool fileShadow, std::string_view owner, std::string via = {} )
    {
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

        emitValueRef( i, j, name, s, fileShadow, owner, std::move( via ) );
    }

    // A node a method value may be written as: Go `b.opPlan` (methodValueAt), C++ `&Cls::m` (memberPointerValueAt).
    bool memberValueKind( const char* t ) const noexcept
    {
        return ( m_slotByName && kindIs( t, "selector_expression" ) )
            || ( m_slot != nullptr && m_slot->memberPointers && kindIs( t, "qualified_identifier" ) );
    }
    void memberValueAt( std::size_t i )
    {
        if( m_slotByName )
        {
            methodValueAt( i );   // IX1-V2: Go `f = b.opPlan` (a method value of the enclosing method's own receiver)
        }
        else
        {
            memberPointerValueAt( i );   // FN-SLOT S2: C++ `&Cls::m` (a pointer to member function)
        }
    }

    // IX1-V2 (Go): `recv.m` in a value position, where recv is the enclosing METHOD's own receiver (no closer scope redeclares
    // it): a Value row naming m with memberRoot = the receiver's type name, so the join resolves it to that type's method m
    // only (valuerefindex.h resolveName), never to a same-named method of another type. Any other `x.m` stays a floor (x's
    // type is not read here).
    void methodValueAt( std::size_t i )
    {
        const TSNode n   = m_anc[i].node;
        const TSNode op  = child( n, m_fOperand );
        const TSNode fld = child( n, m_fField );
        if( ts_node_is_null( op ) || ts_node_is_null( fld ) || !kindIs( ts_node_type( op ), "identifier" ) || i < 2 )
        {
            return;
        }
        const std::size_t d = declaringScope( text( op ) );
        if( d == 0 || !kindIs( ts_node_type( m_scopes[d].node ), "method_declaration" ) )
        {
            return;
        }
        const TSNode rl = child( m_scopes[d].node, m_fReceiver );
        const TSNode rp = ts_node_is_null( rl ) ? TSNode{} : ts_node_named_child( rl, 0 );
        if( ts_node_is_null( rp ) || text( child( rp, m_fName ) ) != text( op ) )
        {
            return;   // a parameter or local of the method, not its receiver
        }
        TSNode rt = child( rp, m_fType );
        if( !ts_node_is_null( rt ) && kindIs( ts_node_type( rt ), "pointer_type" ) )
        {
            rt = ts_node_named_child( rt, 0 );
        }
        const std::string_view owner = goTypeName( rt );
        if( owner.empty() )
        {
            return;
        }
        std::size_t j = i;
        while( j > 1 && transparent( j ) )
        {
            --j;
        }
        Slot s;
        if( !classify( i, j, s ) )
        {
            return;   // the callee of a call (`b.opPlan( x )`), an operand: not a value use
        }
        landValue( i, j, text( fld ), s, false, owner );
    }

    // FN-SLOT S2 (C++, model.h kVrSlotLangs memberPointers): `&Cls::m` in a value position — a Value row naming m with memberRoot
    // = Cls (the class segment written last before m; a template `Cls<T>` is Cls), resolved to that class's method m only
    // (valuerefindex.h ownedBy). A bare `Cls::m` (a static member or a namespace function), an operator or destructor name, and
    // a member pointer to data (no method m) are no rows.
    void memberPointerValueAt( std::size_t i )
    {
        if( i < 2 || !kindIs( m_anc[i - 1].kind, "pointer_expression" ) || text( ts_node_child( m_anc[i - 1].node, 0 ) ) != "&" )
        {
            return;
        }
        // the written chain `[::]a::b::Cls::m`: every scope segment, the class last
        std::vector<std::string_view> segs;
        TSNode                        scope = child( m_anc[i].node, m_fScope );
        TSNode                        name  = child( m_anc[i].node, m_fName );
        const bool                    anchored = ts_node_is_null( scope );
        for( int guard = 0; guard < 8; ++guard )
        {
            if( !ts_node_is_null( scope ) )
            {
                segs.push_back( vrScopeSegment( scope, m_src ) );
            }
            if( ts_node_is_null( name ) || !kindIs( ts_node_type( name ), "qualified_identifier" ) )
            {
                break;
            }
            scope = child( name, m_fScope );
            name  = child( name, m_fName );
        }
        if( segs.empty() || segs.back().empty() || ts_node_is_null( name ) || !kindIs( ts_node_type( name ), "identifier" ) )
        {
            return;   // `&::f`: the global namespace, no class
        }
        const std::string_view owner = segs.back();
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
        landValue( i, j, text( name ), s, false, owner, memberScopeOf( segs, anchored ) );
    }

    // model.h VrMemberScope of a `&[::]a::Cls::m` written in segs (the class last): the qualifier, the enclosing scope, the directives.
    std::string memberScopeOf( const std::vector<std::string_view>& segs, bool anchored ) const
    {
        std::string qualifier = anchored ? "::" : "";
        for( std::size_t k = 0; k + 1 < segs.size(); ++k )
        {
            qualifier += k == 0 ? "" : "::";
            qualifier += segs[k];
        }
        if( segs.size() == 1 && !anchored )
        {
            qualifier = std::string( m_usings.qualifierOf( segs.back() ) );   // `using ns::Cls;` then a bare `&Cls::m`
        }
        return qualifier + kVrMemberScopeSep + vrEnclosingScopePath( m_anc, m_anc.size() - 1, m_src ) + kVrMemberScopeSep + m_usings.directivesJoined();
    }

    // IX1-V2: a PARAMETER (`impl`, position k of the function `fnName` declared at scope d) stored into a field slot
    // (goValueSlot: `Command{ EvalRW: impl }`, `x.F = impl`) — a slot fact (model.h kValueRefSlotParamScope), no row.
    void paramSlotFact( std::size_t i, std::size_t d, std::string_view name )
    {
        const VrScope& sc = m_scopes[d];
        if( !m_slotByName || !sc.isFunction || sc.fnName.empty() || i < 2 )
        {
            return;
        }
        const auto at = std::ranges::find( sc.params, name );
        if( at == sc.params.end() || std::ranges::count( sc.params, name ) != 1 )
        {
            return;
        }
        std::size_t j = i;
        while( j > 1 && transparent( j ) )
        {
            --j;
        }
        Slot   s;
        RawRef r;
        if( !classify( i, j, s ) )
        {
            return;
        }
        goValueSlot( j, r );
        if( r.memberPath.empty() )
        {
            return;
        }
        r.fileId        = m_fileId;
        r.startByte     = ts_node_start_byte( m_anc[i].node );
        r.line          = ts_node_start_point( m_anc[i].node ).row + 1;
        r.lang          = m_lang;
        r.role          = RefRole::Value;
        r.qualifier     = std::string( 1, kValueRefSlotParamScope );   // name stays "": no identifier is empty, so no row
        r.recvVar       = std::string( sc.fnName );
        r.argCount      = static_cast<std::uint16_t>( std::min<std::ptrdiff_t>( at - sc.params.begin(), 0xFFFF ) );
        r.argCountKnown = true;
        m_out.push_back( std::move( r ) );
    }

    // REGISTRAR (model.h kValueRefRegParamScope; read by src/regindex.h): parameter `name` of METHOD scope d (its enclosing scope
    // is a class body, its first parameter `self`) at anc[i], reached through tuple/list/parenthesis wrappers only, is either
    //   an argument of `self.<field>.<store>( … )` (store one of the language row's containerStores), or
    //   the right side of `self.<field>[ … ] = …`.
    // Records the fact (method, parameter position after self, field). A parameter with a default value (`sender=None`) records
    // nothing: it is an option stored beside the receiver, and a positional argument there is not a registered value. Nor does a method
    // whose other parameters are not provably beside the point (pyOtherParamUsed: a required one used beyond the subscript key of the store,
    // a defaulted one stored into `self`). Anything else — a store into a local, a store through
    // another object, a call of the parameter — records nothing (no fact: never a registrar).
    void paramRegFact( std::size_t i, std::size_t d, std::string_view name )
    {
        if( m_regStores.empty() || d == 0 || i < 3 )
        {
            return;
        }
        const VrScope& sc = m_scopes[d];
        if( !sc.isFunction || sc.fnName.empty() || !m_scopes[d - 1].isClass || sc.params.empty() || sc.params.front() != "self" )
        {
            return;
        }
        const auto at = std::ranges::find( sc.params, name );
        if( at == sc.params.begin() || at == sc.params.end() || std::ranges::count( sc.params, name ) != 1 )
        {
            return;
        }
        if( pyParamHasDefault( sc.node, name ) )
        {
            return;   // `sender=None`, `weak=True`: an option the registrar stores beside the receiver, never the registered value
        }
        if( pyOtherParamUsed( sc.node, name ) )
        {
            return;   // `self.rx.append( wrap( receiver ) ); self.fl.append( sender )`: the stored one may be the option, not the value
        }
        std::size_t j = i;
        while( j > 1 && ( kindIs( m_anc[j - 1].kind, "tuple" ) || kindIs( m_anc[j - 1].kind, "list" )
                          || kindIs( m_anc[j - 1].kind, "parenthesized_expression" ) ) )
        {
            --j;
        }
        std::string_view field;
        const VrAnc&     p = m_anc[j - 1];
        if( kindIs( p.kind, "argument_list" ) && j >= 2 && kindIs( m_anc[j - 2].kind, "call" ) )
        {
            // `self.<field>.<store>`: an attribute whose object is the attribute `self.<field>`
            const TSNode fn = child( m_anc[j - 2].node, m_fFunction );
            if( ts_node_is_null( fn ) || !kindIs( ts_node_type( fn ), "attribute" ) )
            {
                return;
            }
            const std::string_view store = text( child( fn, m_fAttribute ) );
            if( std::ranges::find( m_regStores, store ) == m_regStores.end() )
            {
                return;
            }
            field = selfField( child( fn, m_fObject ) );
        }
        else if( kindIs( p.kind, "assignment" ) && m_anc[j].field == m_fRight )
        {
            const TSNode lhs = child( p.node, m_fLeft );
            if( ts_node_is_null( lhs ) || !kindIs( ts_node_type( lhs ), "subscript" ) )
            {
                return;
            }
            field = selfField( ts_node_named_child( lhs, 0 ) );
        }
        if( field.empty() )
        {
            return;
        }
        RawRef r;
        r.fileId        = m_fileId;
        r.startByte     = ts_node_start_byte( m_anc[i].node );
        r.line          = ts_node_start_point( m_anc[i].node ).row + 1;
        r.lang          = m_lang;
        r.role          = RefRole::Value;
        r.qualifier     = std::string( 1, kValueRefRegParamScope );   // name stays "": no identifier is empty, so no row
        r.recvVar       = std::string( sc.fnName );
        r.argCount      = static_cast<std::uint16_t>( std::min<std::ptrdiff_t>( at - sc.params.begin() - 1, 0xFFFF ) );
        r.argCountKnown = true;
        r.memberPath    = std::string( field );
        m_out.push_back( std::move( r ) );
    }
    // `self.<field>` → field; anything else → "".
    std::string_view selfField( TSNode n ) const
    {
        if( ts_node_is_null( n ) || !kindIs( ts_node_type( n ), "attribute" ) )
        {
            return {};
        }
        const TSNode obj = child( n, m_fObject );
        if( ts_node_is_null( obj ) || !kindIs( ts_node_type( obj ), "identifier" ) || text( obj ) != "self" )
        {
            return {};
        }
        return text( child( n, m_fAttribute ) );
    }

    // The Value row of identifier anc[i] (effective position anc[j]) landing in slot `s`.
    void emitValueRef( std::size_t i, std::size_t j, std::string_view name, Slot& s, bool fileShadow, std::string_view owner, std::string via )
    {
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
        if( s.litAt != 0 )
        {
            r.qualifier += "@" + std::to_string( s.litAt );   // REGISTRAR: the object literal (qualifier[2..], read only by regindex.h)
        }
        valueSlot( j, r );   // IX-1: a struct-field slot's type and field (inert without a slot row)
        r.memberRoot = std::string( owner );   // IX1-V2: a method value's receiver type (methodValueAt), "" otherwise
        r.memberVia  = std::move( via );       // FN-SLOT S2: C++ `&Cls::m` — where it was written (model.h VrMemberScope), "" otherwise
        m_out.push_back( std::move( r ) );
    }

    // REGISTRAR (model.h kRegLangs, form ProviderRecord; read by src/regindex.h): is the object literal anc[k] in a position that is
    // never conditional, repeated or rebound? An ALLOWLIST: it is a direct argument of a call (`register( { … } )`, `@Module( { … } )`),
    // the initialiser of a `const` (bound exactly once, never reassigned), or an element / property value of an array / object literal
    // that is itself in such a position. A ternary, `||` / `&&`, a `return`, an assignment, a `let` / `var`, a spread or a cast is none of
    // these: a `provide` and a `useClass` read from there may belong to two different objects.
    bool providerLiteralDirect( std::size_t k, int depth = 0 ) const
    {
        if( k == 0 || depth > 8 )
        {
            return false;
        }
        const VrAnc& p = m_anc[k - 1];
        const VrAnc& c = m_anc[k];
        if( kindIs( p.kind, "arguments" ) || kindIs( p.kind, "argument_list" ) )
        {
            return true;
        }
        if( kindIs( p.kind, "variable_declarator" ) )
        {
            return c.field == m_fValue && k >= 2 && kindIs( m_anc[k - 2].kind, "lexical_declaration" )
                && text( ts_node_child( m_anc[k - 2].node, 0 ) ) == "const";
        }
        if( kindIs( p.kind, "array" ) )
        {
            return providerLiteralDirect( k - 1, depth + 1 );
        }
        if( kindIs( p.kind, "pair" ) && c.field == m_fValue && k >= 2 && kindIs( m_anc[k - 2].kind, "object" ) )
        {
            return providerLiteralDirect( k - 2, depth + 1 );
        }
        return false;
    }
    // Mark slot `s` with the object literal anc[k] it is read from (qualifier "@<start byte>"): only for a ProviderRecord language, a value
    // written bare (`useClass: Impl`, not `Impl ? a : b`) and a literal providerLiteralDirect proves. regindex.h pairs a `provide` with a
    // value only when both carry the SAME mark.
    void markProviderLiteral( Slot& s, bool bare, std::size_t k ) const
    {
        const RegLang* row = regLang( m_lang );
        if( bare && row != nullptr && row->form == RegForm::ProviderRecord && k > 0 && kindIs( m_anc[k].kind, "object" ) && providerLiteralDirect( k ) )
        {
            s.litAt = ts_node_start_byte( m_anc[k].node ) + 1;
        }
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
            s.into = cont + "." + vrClean( text( self.node ) );
            s.container = id;
            s.key = "." + std::string( text( self.node ) );
            s.scope = id.empty() ? 'x' : 'f';
            markProviderLiteral( s, i == j, j - 1 );
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
            markProviderLiteral( s, i == j, j - 2 );
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
            if( m_slotByName && kindIs( pt, "assignment_statement" ) )
            {
                // IX1-V2: Go `x.F = fn` / `x.a.F = fn` — the slot is the field as written (goValueSlot types it), the container x
                const TSNode lhsList = child( p.node, m_fLeft );
                const TSNode lhs     = ts_node_is_null( lhsList ) ? TSNode{} : ts_node_named_child( lhsList, idx );
                if( !ts_node_is_null( lhs ) && kindIs( ts_node_type( lhs ), "selector_expression" ) )
                {
                    const TSNode obj = child( lhs, m_fOperand );
                    s.into = vrClean( text( lhs ) );
                    s.key  = "." + std::string( text( child( lhs, m_fField ) ) );
                    s.container = !ts_node_is_null( obj ) && kindIs( ts_node_type( obj ), "identifier" ) ? std::string( text( obj ) ) : std::string();
                    s.scope = s.container.empty() ? 'x' : 'f';
                    return true;
                }
            }
            const std::string nm( nthName( p.node, kindIs( pt, "var_spec" ), idx ) );
            s.into = nm;
            s.container = nm;
            s.scope = 'f';
            return !nm.empty();
        }
        if( ( kindIs( pt, "assignment_expression" ) || kindIs( pt, "assignment" )
              || ( kindIs( pt, "augmented_assignment_expression" ) && isLogicalAssignment( p.node ) ) ) && c.field == m_fRight )
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

    // ── slot-type join (IX-1) ──────────────────────────────────────────────────────────────────────────
    // A struct type's KEY: its tag (`struct cmd_entry` → "cmd_entry") or a typedef name (`Meter`), plus whether the
    // `struct` / `union` keyword wrote it. An anonymous struct is the name a typedef gives it, else "@LINE" (the struct's
    // own line: valuerefindex.h matches it in its own file only). Anything else (a scalar, `void`, a qualified or template
    // type) has no key: a declaration of it types nothing.
    std::pair<std::string, bool> slotTypeKey( TSNode ty, TSNode parent, const char* parentKind ) const
    {
        if( ts_node_is_null( ty ) )
        {
            return {};
        }
        const char* t = ts_node_type( ty );
        if( kindIs( t, "type_identifier" ) )
        {
            return { std::string( text( ty ) ), false };
        }
        if( !( kindIs( t, "struct_specifier" ) || kindIs( t, "union_specifier" ) || kindIs( t, "class_specifier" ) ) )
        {
            return {};
        }
        const bool   kw = !kindIs( t, "class_specifier" );
        const TSNode nm = child( ty, m_fName );
        if( !ts_node_is_null( nm ) )
        {
            return kindIs( ts_node_type( nm ), "type_identifier" ) ? std::pair<std::string, bool>{ std::string( text( nm ) ), kw }
                                                                   : std::pair<std::string, bool>{};
        }
        if( kindIs( parentKind, "type_definition" ) )
        {
            const std::string_view td = typedefName( parent );
            return td.empty() ? std::pair<std::string, bool>{} : std::pair<std::string, bool>{ std::string( td ), kw };
        }
        return { "@" + std::to_string( ts_node_start_point( ty ).row + 1 ), kw };
    }

    // slotTypeKey's key as a record carries it: led by kValueRefSlotTagMark when the `struct` / `union` keyword spelled it.
    static std::string slotCtor( const std::string& key, bool kw )
    {
        return kw && !key.empty() ? kValueRefSlotTagMark + key : key;
    }

    // The name a `typedef … NAME;` declares (the pointer form `typedef struct x *xp;` is read by noteSlotTypes, not here).
    std::string_view typedefName( TSNode td ) const noexcept
    {
        return fieldChildTextOfKind( td, NodeField::Declarator, "type_identifier", m_src );
    }

    // A function-POINTER declarator `(*f)( … )` (any depth of pointers inside the parentheses): a stored function.
    bool fnPointerDeclarator( TSNode d ) const noexcept
    {
        if( ts_node_is_null( d ) || !kindIs( ts_node_type( d ), "function_declarator" ) )
        {
            return false;
        }
        const TSNode inner = child( d, m_fDeclarator );
        return !ts_node_is_null( inner ) && kindIs( ts_node_type( inner ), "parenthesized_declarator" );
    }

    // Calls `fn( declarator )` for each declarator child of a declaring node (a declaration may declare several).
    template<typename Fn>
    void forEachDeclarator( TSNode n, Fn&& fn ) const
    {
        ChildCursor c( n );
        ts_tree_cursor_reset( &c.cur, n );
        if( !ts_tree_cursor_goto_first_child( &c.cur ) )
        {
            return;
        }
        do
        {
            if( ts_tree_cursor_current_field_id( &c.cur ) == m_fDeclarator )
            {
                fn( ts_tree_cursor_current_node( &c.cur ) );
            }
        }
        while( ts_tree_cursor_goto_next_sibling( &c.cur ) );
    }

    // The declared struct types of a declaring node's names, into the innermost scope (beside harvest's names); a typedef
    // of a struct is a slot fact (alias → struct).
    void noteSlotTypes( TSNode n, const char* t )
    {
        if( m_slot == nullptr || noteMacroCast( n, t ) )
        {
            return;
        }
        if( kindIs( t, "type_definition" ) )
        {
            // `typedef struct T NAME;` and the pointer form `typedef struct T *NAME_p;` (a receiver `p->f` derefs it, and no
            // struct literal has a pointer type, so NAME_p → T is exact for the join), each declarator its own alias.
            const auto [ key, kw ] = slotTypeKey( child( n, m_fType ), n, t );
            forEachDeclarator( n, [ & ]( TSNode d )
            {
                m_scalarTypedefs.note( d, m_scalarTypedefs.scalar( child( n, m_fType ), m_src ), m_fDeclarator, m_src );
                if( kindIs( ts_node_type( d ), "pointer_declarator" ) )
                {
                    d = child( d, m_fDeclarator );
                }
                if( !ts_node_is_null( d ) && kindIs( ts_node_type( d ), "type_identifier" ) )
                {
                    noteSlotAlias( n, text( d ), slotCtor( key, kw ) );
                }
            } );
            return;
        }
        if( kindIs( t, "alias_declaration" ) )
        {
            // C++ `using SA = S;` (a pointer `using SP = S *;` too: the descriptor's own type is the struct)
            TSNode ty = child( n, m_fType );
            if( !ts_node_is_null( ty ) && kindIs( ts_node_type( ty ), "type_descriptor" ) )
            {
                ty = child( ty, m_fType );
            }
            const auto [ key, kw ] = slotTypeKey( ty, n, t );
            noteSlotAlias( n, text( child( n, m_fName ) ), slotCtor( key, kw ) );
            return;
        }
        if( !( kindIs( t, "declaration" ) || kindIs( t, "parameter_declaration" ) || kindIs( t, "optional_parameter_declaration" )
               || kindIs( t, "field_declaration" ) ) )
        {
            return;
        }
        const auto [ key, kw ] = slotTypeKey( child( n, m_fType ), n, t );
        if( key.empty() )
        {
            return;   // a scalar / void / pointer-to-function declaration: its names stay declared, untyped (no slot call)
        }
        VrScope& sc = m_scopes.back();
        forEachDeclarator( n, [ & ]( TSNode d )
        {
            if( declaresFunction( d ) || fnPointerDeclarator( d ) || ( kindIs( ts_node_type( d ), "init_declarator" ) && fnPointerDeclarator( child( d, m_fDeclarator ) ) ) )
            {
                return;   // a prototype, or a function pointer returning the struct: not an object of it
            }
            const std::string_view nm = declaratorName( d );
            if( !nm.empty() )
            {
                sc.types.push_back( { nm, key, kw } );
            }
        } );
    }

    // A struct / union / class BODY as the walk enters its specifier: its field order (positional initializers), its
    // function-pointer fields (the C++ gate) and one slot fact per field declared with a struct type.
    // A file-scope or block-scope `using ns::Cls;` / `using namespace ns;` (C++ member-pointer rows only) feeds m_usings. A CLASS MEMBER's
    // `using B::B;` (inheriting constructors) / `using B::m;` names a member, never a class a bare spelling reaches: its parent is the
    // class body (field_declaration_list), and noting it would make the later bare `&B::m` decline as an external class (CR 4415276397).
    void noteUsing( TSNode n, const char* t )
    {
        if( m_slot == nullptr || !m_slot->memberPointers || !kindIs( t, "using_declaration" ) )
        {
            return;
        }
        if( !m_anc.empty() && kindIs( m_anc.back().kind, "field_declaration_list" ) )
        {
            return;
        }
        m_usings.note( n, m_src );
    }
    void noteStructBody( TSNode n, const char* t )
    {
        if( m_slot == nullptr || !( kindIs( t, "struct_specifier" ) || kindIs( t, "union_specifier" ) || kindIs( t, "class_specifier" ) ) )
        {
            return;
        }
        const TSNode body = fieldChild( n, NodeField::Body );
        if( ts_node_is_null( body ) || m_anc.empty() )
        {
            return;
        }
        const VrAnc& parent = m_anc.back();
        auto [ owner, kw ] = slotTypeKey( n, parent.node, parent.kind );
        if( owner.empty() )
        {
            return;
        }
        if( owner.front() != '@' )   // an anonymous struct's "@LINE" key is its own file's already
        {
            emitSlotFact( n, owner, kValueRefSlotBodyRel + vrEnclosingScopePath( m_anc, m_anc.size(), m_src ), vrBodyDigest( text( body ) ) );
        }
        VrStructFields sf;
        sf.key = owner;
        if( !ts_node_is_null( firstChildOfKind( n, true, { "base_class_clause" } ) ) )
        {
            sf.exactUpTo = 0;   // C++ bases are initialized first, and a base's own list may be brace-elided: no index is provable
        }
        ChildCursor c( body );
        forEachNamedChild( body, c.cur, [ & ]( TSNode k )
        {
            const char* kt = ts_node_type( k );
            if( kindIs( kt, "preproc_if" ) || kindIs( kt, "preproc_ifdef" ) )
            {
                sf.exactUpTo = std::min( sf.exactUpTo, sf.fields.size() );   // the fields inside depend on the build: later indexes are unprovable
                return true;
            }
            if( !kindIs( kt, "field_declaration" ) )
            {
                return true;
            }
            const TSNode ftNode = child( k, m_fType );
            const auto [ ftype, fkw ] = slotTypeKey( ftNode, k, "field_declaration" );
            const bool   isStatic = vrStaticMember( k, m_src );   // C++: a static data member is no part of the aggregate
            const auto [ structTyped, unseen ] = vrFieldTypeClass( ftNode, knownStruct( ftype ), m_scalarTypedefs, m_src );
            if( !isStatic && vrAnonymousMember( k, ftNode, m_fDeclarator, m_fName ) )
            {
                sf.fields.push_back( { {}, true, false } );   // an anonymous struct / union MEMBER: one position, no name a call writes
                return true;
            }
            forEachDeclarator( k, [ & ]( TSNode d )
            {
                if( declaresFunction( d ) )
                {
                    return;   // a member function declaration: no data field, no initializer position
                }
                const std::string_view nm = declaratorName( d );
                if( !isStatic )
                {
                    const char* dt      = ts_node_type( d );
                    const bool  isArray = kindIs( dt, "array_declarator" );
                    sf.fields.push_back( { nm, isArray || ( structTyped && kindIs( dt, "field_identifier" ) ), isArray, unseen && kindIs( dt, "field_identifier" ) } );
                }
                if( nm.empty() )
                {
                    return;
                }
                if( fnPointerDeclarator( d ) )
                {
                    m_callableFields.emplace_back( owner, nm );
                }
                else if( !ftype.empty() )
                {
                    emitSlotFact( k, owner, nm, slotCtor( ftype, fkw ) );
                }
            } );
            return true;
        } );
        m_structs.push_back( std::move( sf ) );
    }


    // A type key this file holds a struct body for (directly, or through this file's aliases).
    bool knownStruct( std::string_view key ) const
    {
        return !key.empty() && !std::ranges::contains( m_scalarTypedefs.names, key ) && std::ranges::find( m_structs, m_aliases.resolve( key ), &VrStructFields::key ) != m_structs.end();
    }




    // A typedef / using alias of a struct type: a slot fact (valuerefindex.h unaliases a receiver through it) and this file's
    // own alias map (the C++ gate reads the struct an alias names in this file).
    // FN-SLOT S2 (c): a function-like macro whose whole body is ONE pointer cast to a named type, `#define As_Row( x )
    // ( ( const RowClass* )( … ) )`, is an alias fact of the key "()As_Row" (kVrSlotMacroCastMark + name) for that type, so a
    // slot call `As_Row( this )->writeField( … )` (slotThroughAt) keys RowClass wherever the macro is defined. Anything else
    // in the body (`( ( T* )( x ) )->klass`, two casts, a non-pointer cast) records nothing.
    // Returns whether `n` is a macro definition (handled here).
    bool noteMacroCast( TSNode n, const char* t )
    {
        if( !kindIs( t, "preproc_function_def" ) )
        {
            return false;
        }
        emitMacroCast( n );
        return true;
    }
    void emitMacroCast( TSNode n )
    {
        const std::string_view name = text( child( n, m_fName ) );
        std::string_view       v    = text( child( n, m_fValue ) );
        const auto trim = [ & ]()
        {
            while( !v.empty() && ( v.front() == ' ' || v.front() == '\t' || v.front() == '\\' || v.front() == '\n' || v.front() == '\r' ) )
            {
                v.remove_prefix( 1 );
            }
            while( !v.empty() && ( v.back() == ' ' || v.back() == '\t' || v.back() == '\n' || v.back() == '\r' ) )
            {
                v.remove_suffix( 1 );
            }
        };
        trim();
        if( name.empty() || v.size() < 6 || v.front() != '(' || v.back() != ')' )
        {
            return;
        }
        int depth = 0;
        for( std::size_t k = 0; k < v.size(); ++k )
        {
            depth += v[k] == '(' ? 1 : v[k] == ')' ? -1 : 0;
            if( depth == 0 && k + 1 != v.size() )
            {
                return;   // the first parenthesis closes before the end: not one parenthesised cast expression
            }
        }
        v = v.substr( 1, v.size() - 2 );
        trim();
        if( v.empty() || v.front() != '(' )
        {
            return;
        }
        const std::size_t close = v.find( ')' );
        if( close == std::string_view::npos )
        {
            return;
        }
        std::string_view cast = v.substr( 1, close - 1 );
        bool             kw   = false;
        std::string_view type;
        std::size_t      stars = 0;
        while( !cast.empty() )
        {
            std::size_t w = 0;
            while( w < cast.size() && ( cast[w] == '_' || ( cast[w] >= 'a' && cast[w] <= 'z' ) || ( cast[w] >= 'A' && cast[w] <= 'Z' ) || ( cast[w] >= '0' && cast[w] <= '9' ) ) )
            {
                ++w;
            }
            const std::string_view tok = w > 0 ? cast.substr( 0, w ) : cast.substr( 0, 1 );
            cast.remove_prefix( tok.size() );
            if( tok == " " || tok == "\t" || tok == "const" || tok == "volatile" )
            {
                continue;
            }
            if( tok == "struct" || tok == "union" )
            {
                kw = true;
            }
            else if( tok == "*" )
            {
                ++stars;
            }
            else if( w > 0 && type.empty() && stars == 0 )
            {
                type = tok;
            }
            else
            {
                return;   // a second type word (`unsigned long`), a template, a reference: not one named pointer type
            }
        }
        if( type.empty() || stars != 1 )
        {
            return;
        }
        emitSlotFact( n, std::string( kVrSlotMacroCastMark ) + std::string( name ), {}, slotCtor( std::string( type ), kw ) );
    }

    void noteSlotAlias( TSNode at, std::string_view alias, const std::string& ctor )   // ctor: slotCtor( key, kw )
    {
        const std::string_view key = ctor.starts_with( kValueRefSlotTagMark ) ? std::string_view( ctor ).substr( 1 ) : std::string_view( ctor );
        if( alias.empty() || key.empty() || key == alias )
        {
            return;
        }
        emitSlotFact( at, std::string( alias ), {}, ctor );
        m_aliases.pairs.emplace_back( std::string( alias ), std::string( key ) );
    }

    void emitSlotFact( TSNode at, std::string owner, std::string_view field, const std::string& type )
    {
        RawRef r;
        r.fileId     = m_fileId;
        r.startByte  = ts_node_start_byte( at );
        r.line       = ts_node_start_point( at ).row + 1;
        r.lang       = m_lang;
        r.role       = RefRole::Value;
        r.qualifier  = std::string( 1, kValueRefSlotFactScope );   // name stays "": no identifier is empty, so no row
        r.recvVar    = std::move( owner );
        r.composeRel = std::string( field );
        r.memberCtor = type;
        m_out.push_back( std::move( r ) );
    }

    // The struct type a name is declared with, innermost scope first: declared = some scope declares it; key "" with
    // declared = true is a non-struct declaration (no slot); declared = false is a name no scope of this file declares.
    struct VrTypeOf
    {
        bool             declared = false;
        std::string_view key;
        bool             structKw = false;
    };
    VrTypeOf typeOfName( std::string_view name ) const
    {
        for( std::size_t k = m_scopes.size(); k > 0; --k )
        {
            const VrScope& sc = m_scopes[k - 1];
            if( std::ranges::find( sc.decls, name ) == sc.decls.end() )
            {
                continue;
            }
            for( auto it = sc.types.rbegin(); it != sc.types.rend(); ++it )
            {
                if( it->name == name )
                {
                    return { true, it->type, it->structKw };
                }
            }
            return { true, {}, false };
        }
        return {};
    }

    // A single-dimension array declarator `name[]` / `name[N]`: the initializer list below it IS the array.
    bool arrayDeclarator( TSNode d, bool& multi ) const noexcept
    {
        multi = false;
        if( ts_node_is_null( d ) || !kindIs( ts_node_type( d ), "array_declarator" ) )
        {
            return false;
        }
        const TSNode inner = child( d, m_fDeclarator );
        multi = !ts_node_is_null( inner ) && kindIs( ts_node_type( inner ), "array_declarator" );
        return true;
    }

    // The struct type of the initializer list anc[k]: a struct object's list (`T x = { … }`), one element of a
    // one-dimension array's list (`T a[] = { { … } }`), or a compound literal `(T){ … }`. "" otherwise — the array's own
    // list, a nested struct field's list (its field type is not read here: a disclosed floor), a multi-dimension array.
    std::pair<std::string, bool> literalType( std::size_t k ) const
    {
        if( k < 2 || !kindIs( m_anc[k].kind, "initializer_list" ) )
        {
            return {};
        }
        const VrAnc& up = m_anc[k - 1];
        bool         multi = false;
        if( kindIs( up.kind, "init_declarator" ) )
        {
            if( arrayDeclarator( child( up.node, m_fDeclarator ), multi ) || !kindIs( m_anc[k - 2].kind, "declaration" ) )
            {
                return {};
            }
            return slotTypeKey( child( m_anc[k - 2].node, m_fType ), m_anc[k - 2].node, m_anc[k - 2].kind );
        }
        if( kindIs( up.kind, "initializer_list" ) && k >= 3 && kindIs( m_anc[k - 2].kind, "init_declarator" ) )
        {
            if( !arrayDeclarator( child( m_anc[k - 2].node, m_fDeclarator ), multi ) || multi || !kindIs( m_anc[k - 3].kind, "declaration" ) )
            {
                return {};
            }
            return slotTypeKey( child( m_anc[k - 3].node, m_fType ), m_anc[k - 3].node, m_anc[k - 3].kind );
        }
        if( kindIs( up.kind, "compound_literal_expression" ) )
        {
            TSNode ty = child( up.node, m_fType );
            if( !ts_node_is_null( ty ) && kindIs( ts_node_type( ty ), "type_descriptor" ) )
            {
                ty = child( ty, m_fType );
            }
            return slotTypeKey( ty, up.node, up.kind );
        }
        return {};
    }

    // The field chain of a member access, root first: `wme->mode->command` → root `wme`, chain "mode.command";
    // subscripts and parentheses are crossed (`t[ i ].f` → root `t`, chain "f"). A null root: not an identifier.
    TSNode fieldChain( TSNode f, std::string& chain, TSNode* base = nullptr ) const
    {
        chain = std::string( text( child( f, m_fField ) ) );
        TSNode x = child( f, m_fArgument );
        for( int guard = 0; guard < 8 && !ts_node_is_null( x ); ++guard )
        {
            const char* xt = ts_node_type( x );
            if( kindIs( xt, "field_expression" ) )
            {
                chain = std::string( text( child( x, m_fField ) ) ) + "." + chain;
                x     = child( x, m_fArgument );
            }
            else if( kindIs( xt, "subscript_expression" ) )
            {
                x = child( x, m_fArgument );
            }
            else if( kindIs( xt, "parenthesized_expression" ) )
            {
                x = ts_node_named_child( x, 0 );
            }
            else
            {
                break;
            }
        }
        if( base != nullptr )
        {
            *base = x;
        }
        return !ts_node_is_null( x ) && kindIs( ts_node_type( x ), "identifier" ) ? x : TSNode{};
    }

    // The type of the literal list anc[k] a designated field `path` is written in. FN-SLOT S2 (c): a NESTED designated literal
    // `.super = { .super = { .display = f } }` with no type of its own is a field of the enclosing literal's field, so the path
    // climbs (super.super.display) to the first literal with a type; `path` keeps the field alone when none has one.
    std::pair<std::string, bool> designatedType( std::size_t k, std::string& path ) const
    {
        std::string climbed = path;
        for( int guard = 0; guard < 4; ++guard, k -= 2 )
        {
            auto typed = literalType( k );
            if( !typed.first.empty() )
            {
                path = std::move( climbed );
                return typed;
            }
            if( k < 3 || !kindIs( m_anc[k].kind, "initializer_list" ) || !kindIs( m_anc[k - 1].kind, "initializer_pair" ) )
            {
                break;
            }
            const std::string_view up = vrDesignatedField( m_anc[k - 1].node, m_fDesignator, m_src );
            if( up.empty() )
            {
                break;
            }
            climbed = std::string( up ) + "." + climbed;
        }
        return {};
    }

    // FN-SLOT S2 (C++): the member-pointer operand of a `( obj.*x.f )( … )` callee — the grammar reads `obj.*x.f` as the field
    // chain obj → x → f whose FIRST hop is the `.*` operator, so the operand's root is that hop's field (`x`) and its chain the
    // hops after it ("f"). A null root: no `.*`, `.*` last (`( obj.*pmf )( … )`, a member pointer in a plain variable: no field
    // slot), or a non-field hop after it.
    TSNode memberPointerChain( TSNode f, std::string& chain ) const
    {
        if( ts_node_is_null( f ) || !kindIs( ts_node_type( f ), "parenthesized_expression" ) )
        {
            return {};
        }
        TSNode x = ts_node_named_child( f, 0 );
        std::string tail;
        for( int guard = 0; guard < 8 && !ts_node_is_null( x ) && kindIs( ts_node_type( x ), "field_expression" ); ++guard )
        {
            const TSNode fld = child( x, m_fField );
            if( ts_node_is_null( fld ) || !kindIs( ts_node_type( fld ), "field_identifier" ) )
            {
                return {};
            }
            if( ts_node_child_count( x ) >= 2 && text( ts_node_child( x, 1 ) ) == ".*" )
            {
                if( tail.empty() )
                {
                    return {};
                }
                chain = std::move( tail );
                return fld;
            }
            tail = tail.empty() ? std::string( text( fld ) ) : std::string( text( fld ) ) + "." + tail;
            x    = child( x, m_fArgument );
        }
        return {};
    }

    // IX1-V2 (Go): the type NAME a composite literal's or receiver's type node spells — `Command`, `batcheval.Command` (its final
    // segment; goValueSlot keeps a qualified literal type whole), by ingest_relations.h aliasTargetName. "" for every other type (a map, a slice, an inline struct, a generic
    // instantiation `Box[T]` — a floor): a value stored there lands in a container slot, which the container join answers.
    std::string_view goTypeName( TSNode ty ) const noexcept
    {
        return aliasTargetName( ty, m_src );
    }
    // IX1-V2 (Go): the struct-field slot a Value row (effective position anc[j]) lands in — a keyed element of a composite
    // literal of a NAMED type (`Command{ EvalRW: fn }`: memberPath "EvalRW", memberCtor "Command"), or a field assignment
    // `x.F = fn` / `x.a.F = fn` (memberPath "F", memberCtor "": the receiver's type is not read here, so it joins by the field
    // name alone). A map key, a positional element, a nested literal without its own type, a slice or map literal: no slot.
    void goValueSlot( std::size_t j, RawRef& r ) const
    {
        if( j < 4 )
        {
            return;
        }
        const VrAnc& p = m_anc[j - 1];
        if( kindIs( p.kind, "keyed_element" ) )
        {
            TSNode k = ts_node_named_child( p.node, 0 );
            if( !ts_node_is_null( k ) && kindIs( ts_node_type( k ), "literal_element" ) )
            {
                k = ts_node_named_child( k, 0 );
            }
            if( ts_node_is_null( k ) || !( kindIs( ts_node_type( k ), "identifier" ) || kindIs( ts_node_type( k ), "field_identifier" ) ) )
            {
                return;   // a map key (a string, a constant expression): a container slot, not a field
            }
            if( !kindIs( m_anc[j - 2].kind, "literal_value" ) || !kindIs( m_anc[j - 3].kind, "composite_literal" ) )
            {
                return;   // a nested literal whose type is the outer literal's element type: not read (a floor)
            }
            const TSNode           tyNode = child( m_anc[j - 3].node, m_fType );
            const std::string_view ty     = goTypeName( tyNode );
            if( ty.empty() )
            {
                return;   // a map / slice / inline struct literal: the key is not a field of a named struct type
            }
            r.memberPath = std::string( text( k ) );
            // fix1 F-2: `pkg.T` kept WHOLE (the join maps pkg through the file's import to its directory); a bare `T` is the
            // file's own package's
            r.memberCtor = kindIs( ts_node_type( tyNode ), "qualified_type" ) ? std::string( text( tyNode ) ) : std::string( ty );
            return;
        }
        if( kindIs( p.kind, "assignment_statement" ) && m_anc[j].field == m_fRight && kindIs( m_anc[j].kind, "expression_list" ) && j + 1 < m_anc.size() )
        {
            const TSNode lhsList = child( p.node, m_fLeft );
            const TSNode lhs     = ts_node_is_null( lhsList ) ? TSNode{} : ts_node_named_child( lhsList, m_anc[j + 1].namedIndex );
            if( ts_node_is_null( lhs ) || !kindIs( ts_node_type( lhs ), "selector_expression" ) || opText( p.node ) != "=" )
            {
                return;   // a plain variable (the container join's), or a compound assignment
            }
            const TSNode fld = child( lhs, m_fField );
            if( ts_node_is_null( fld ) || ts_node_named_child_count( lhsList ) != ts_node_named_child_count( m_anc[j].node ) )
            {
                return;   // `a, b.F = f()`: a multi-value call, no position maps one value to one field
            }
            r.memberPath = std::string( text( fld ) );
            r.memberCtor.clear();
        }
    }

    // The slot a Value row (`r`, effective position anc[j]) lands in, when it is a struct field: memberPath = the chain,
    // memberCtor = the declared struct type of the object ("" unknown). Left empty for every other slot.
    void valueSlot( std::size_t j, RawRef& r ) const
    {
        if( m_slotByName )
        {
            goValueSlot( j, r );
            return;
        }
        if( m_slot == nullptr || j < 1 )
        {
            return;
        }
        const VrAnc& p  = m_anc[j - 1];
        const char*  pt = p.kind;
        if( kindIs( pt, "initializer_pair" ) )
        {
            TSNode k = child( p.node, m_fDesignator );
            if( ts_node_is_null( k ) )
            {
                k = ts_node_named_child( p.node, 0 );
            }
            const std::string_view fld = vrDesignatedField( p.node, m_fDesignator, m_src );
            if( ts_node_is_null( k ) || fld.empty() || j < 2 )
            {
                return;   // a nested `.a.b =` / array `[i] =` designator: not one field of this literal's type
            }
            r.memberPath = std::string( fld );
            const auto [ lt, ltKw ] = designatedType( j - 2, r.memberPath );
            r.memberCtor = slotCtor( lt, ltKw );
            return;
        }
        if( kindIs( pt, "initializer_list" ) )
        {
            const auto [ t, tKw ] = literalType( j - 1 );
            if( t.empty() )
            {
                return;   // not a struct literal
            }
            const auto sf = std::ranges::find( m_structs, tKw ? std::string_view( t ) : m_aliases.resolve( t ), &VrStructFields::key );
            const std::ptrdiff_t idx = sf == m_structs.end() ? -1 : vrPositionOf( p.node, m_anc[j].node, *sf, m_fDesignator, m_src );
            if( idx >= 0 )
            {
                r.memberPath = std::string( sf->fields[ static_cast<std::size_t>( idx ) ].name );
                r.memberCtor = slotCtor( t, tKw );
            }
            return;   // an index not provable exactly: no slot (never a guessed field)
        }
        if( kindIs( pt, "assignment_expression" ) && m_anc[j].field == m_fRight )
        {
            const TSNode lhs = child( p.node, m_fLeft );
            if( ts_node_is_null( lhs ) || !kindIs( ts_node_type( lhs ), "field_expression" ) )
            {
                return;
            }
            std::string  chain;
            const TSNode root = fieldChain( lhs, chain );
            if( ts_node_is_null( root ) )
            {
                return;
            }
            const VrTypeOf ty = typeOfName( text( root ) );
            if( ty.declared && ty.key.empty() )
            {
                return;   // a non-struct object
            }
            r.memberPath = std::move( chain );
            r.memberCtor = slotCtor( std::string( ty.key ), ty.structKw );
        }
    }

    // A call through a struct field (`x->f( … )`, `x->a.f( … )`, `t[ i ].f( … )`): one slot Through, never filtered by a
    // fed container (the values arrive from other files). No row when the root is not an identifier (a cast, a call
    // result) or is declared with a non-struct type (`void *`, a scalar); a root no scope of this file declares (an
    // extern, a macro) keeps an empty type, so only the name tier can join it. Under C++'s row: see kVrSlotLangs.
    void slotThroughAt( TSNode call )
    {
        if( m_slot == nullptr )
        {
            return;
        }
        const TSNode f = vrDerefCallee( child( call, m_fFunction ), m_fArgument );
        std::string  chain;
        bool         viaMemberPointer = false;
        const TSNode root = slotCallRoot( call, f, chain, viaMemberPointer );
        if( ts_node_is_null( root ) )
        {
            return;
        }
        const VrTypeOf ty = typeOfName( text( root ) );
        if( ty.declared && ty.key.empty() )
        {
            return;
        }
        const std::size_t      dot   = chain.rfind( '.' );
        const std::string_view field = dot == std::string::npos ? std::string_view( chain ) : std::string_view( chain ).substr( dot + 1 );
        if( !m_slot->everyFieldCall && !viaMemberPointer && !cppFieldCall( ty, dot == std::string::npos, field ) )
        {
            return;   // C++: a struct-keyword receiver, or a direct call through a function-pointer field its type (through this
                      // file's typedef / using aliases) declares in this file
        }
        emitSlotCall( call, f, root, chain, std::string( ty.key ), ty.structKw );
    }
    // The C++ gate on a field call: a struct-keyword receiver, or a direct call through a function-pointer field its type
    // (through this file's typedef / using aliases) declares in this file.
    bool cppFieldCall( const VrTypeOf& ty, bool direct, std::string_view field ) const
    {
        return ty.declared
            && ( ty.structKw
                 || ( direct
                      && std::ranges::find( m_callableFields, std::pair<std::string_view, std::string_view>( m_aliases.resolve( ty.key ), field ),
                                            []( const auto& cf ) { return std::pair<std::string_view, std::string_view>( cf.first, cf.second ); } )
                             != m_callableFields.end() ) );
    }
    // The root of slot call `call`'s callee `f` and its field chain: `x->a.f`, or (C++) the member-pointer operand of
    // `( o.*x.f )`; null when there is none. FN-SLOT S2 (c): a C call receiver `M( … )->f( … )` is emitted here (keyed "()M":
    // the macro's cast type when noteMacroCast recorded one, else the name tier) and answers null.
    TSNode slotCallRoot( TSNode call, TSNode f, std::string& chain, bool& viaMemberPointer )
    {
        if( !ts_node_is_null( f ) && kindIs( ts_node_type( f ), "field_expression" ) )
        {
            TSNode       base;
            const TSNode root = fieldChain( f, chain, &base );
            if( ts_node_is_null( root ) && m_slot->everyFieldCall && macroCastCall( base ) )
            {
                emitSlotCall( call, f, child( base, m_fFunction ), chain, std::string( kVrSlotMacroCastMark ) + std::string( text( child( base, m_fFunction ) ) ), false );
            }
            return root;
        }
        if( !m_slot->memberPointers )
        {
            return {};
        }
        const TSNode root = memberPointerChain( f, chain );
        viaMemberPointer  = !ts_node_is_null( root );
        return root;
    }
    // A slot call Through (model.h kValueRefSlotCallScope): root `root`, field chain `chain`, the root's type key `key`.
    void emitSlotCall( TSNode call, TSNode f, TSNode root, std::string& chain, std::string key, bool kw )
    {
        const std::size_t dot = chain.rfind( '.' );
        RawRef r;
        r.fileId     = m_fileId;
        r.startByte  = ts_node_start_byte( call );
        r.line       = ts_node_start_point( call ).row + 1;
        r.lang       = m_lang;
        r.role       = RefRole::Through;
        r.qualifier  = std::string( 1, kValueRefSlotCallScope );
        r.name       = std::string( text( root ) );
        r.fieldName  = vrClean( text( f ) );
        r.composeRel = "." + ( dot == std::string::npos ? chain : chain.substr( dot + 1 ) );
        r.memberCtor = slotCtor( std::move( key ), kw );
        r.memberPath = std::move( chain );
        m_out.push_back( std::move( r ) );
    }
    // FN-SLOT S2 (c): a call of a bare identifier (a function-like macro, or a function returning a struct pointer) as a field
    // chain's base — the join keys its noteMacroCast fact, and a name with none joins by the field name only.
    bool macroCastCall( TSNode base ) const noexcept
    {
        return !ts_node_is_null( base ) && kindIs( ts_node_type( base ), "call_expression" ) && !ts_node_is_null( child( base, m_fFunction ) )
            && kindIs( ts_node_type( child( base, m_fFunction ) ), "identifier" );
    }

    // ── name-template dispatch (IX-3) ─────────────────────────────────────────────────────────────────
    // A lookup whose NAME is built from a template with a visible literal side: the per-family forms are DATA
    // (kVrPatternLookups); the template shapes are an f-string / JS template literal (its holes are interpolation /
    // template_substitution children) or a `+` with exactly one string-literal operand. A literal name is no template
    // (an ordinary by-name lookup) and a bare variable has no literal side: neither records anything.
    struct VrTemplate
    {
        bool        isTemplate = false;
        std::string prefix;
        std::string suffix;
        bool        callable = true;   // false: the name is tested or stored, never called through (hasattr, `o[ 'p' + e ] = fn`)
    };
    bool isPlainStringNode( TSNode n ) const noexcept
    {
        if( ts_node_is_null( n ) || !kindIs( ts_node_type( n ), "string" ) )
        {
            return false;
        }
        const std::uint32_t k = ts_node_named_child_count( n );
        for( std::uint32_t i = 0; i < k; ++i )
        {
            if( kindIs( ts_node_type( ts_node_named_child( n, i ) ), "interpolation" ) )
            {
                return false;   // a Python f-string is a `string` with interpolation children
            }
        }
        return true;
    }
    VrTemplate templateOf( TSNode n ) const
    {
        VrTemplate out;
        if( ts_node_is_null( n ) )
        {
            return out;
        }
        const char* k = ts_node_type( n );
        if( kindIs( k, "binary_operator" ) || kindIs( k, "binary_expression" ) )
        {
            const TSNode op = child( n, m_fOperator );
            if( ts_node_is_null( op ) || text( op ) != "+" )
            {
                return out;
            }
            const TSNode l  = child( n, m_fLeft );
            const TSNode r  = child( n, m_fRight );
            const bool   ls = isPlainStringNode( l );
            const bool   rs = isPlainStringNode( r );
            if( ls == rs )
            {
                return out;   // two literals are a constant name; no literal operand leaves no visible side
            }
            out.isTemplate = true;
            ( ls ? out.prefix : out.suffix ) = std::string( vrStringContent( text( ls ? l : r ) ) );
            return out;
        }
        const bool py = kindIs( k, "string" );
        if( !py && !kindIs( k, "template_string" ) )
        {
            return out;
        }
        const auto isHole = [ py ]( const char* ck ) { return py ? kindIs( ck, "interpolation" ) : kindIs( ck, "template_substitution" ); };
        const std::uint32_t cnt = ts_node_named_child_count( n );
        TSNode first {}, last {}, open {}, close {};
        for( std::uint32_t i = 0; i < cnt; ++i )
        {
            const TSNode c  = ts_node_named_child( n, i );
            const char*  ck = ts_node_type( c );
            if( isHole( ck ) )
            {
                if( ts_node_is_null( first ) )
                {
                    first = c;
                }
                last = c;
            }
            else if( kindIs( ck, "string_start" ) )
            {
                open = c;
            }
            else if( kindIs( ck, "string_end" ) )
            {
                close = c;
            }
        }
        if( ts_node_is_null( first ) )
        {
            return out;   // no hole: a literal
        }
        // byte spans: the literal text between the opening delimiter and the first hole, and after the last hole
        const std::uint32_t b0 = py ? ( ts_node_is_null( open ) ? ts_node_end_byte( n ) : ts_node_end_byte( open ) ) : ts_node_start_byte( n ) + 1;
        const std::uint32_t e1 = py ? ( ts_node_is_null( close ) ? ts_node_start_byte( n ) : ts_node_start_byte( close ) ) : ts_node_end_byte( n ) - 1;
        const std::uint32_t h0 = ts_node_start_byte( first );
        const std::uint32_t h1 = ts_node_end_byte( last );
        if( b0 > h0 || h1 > e1 || e1 > m_src.size() )
        {
            return out;   // a delimiter shape this reading does not know: no claim
        }
        out.isTemplate = true;
        out.prefix     = std::string( m_src.substr( b0, h0 - b0 ) );
        out.suffix     = std::string( m_src.substr( h1, e1 - h1 ) );
        return out;
    }
    // A literal side the template can be matched on: >= kVrPatternMinLiteral identifier characters and nothing else.
    static bool patternSideUsable( std::string_view s ) noexcept
    {
        return s.size() >= kVrPatternMinLiteral && std::ranges::all_of( s, []( char c )
        {
            return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '$';
        } );
    }
    void emitPattern( TSNode site, TSNode recv, const VrTemplate& t )
    {
        if( !t.isTemplate || ( t.prefix.empty() && t.suffix.empty() ) )
        {
            return;   // no literal side at all (`o[k + '']`, f"{m}"): no name information, like a bare `o[k]`
        }
        const bool pre = patternSideUsable( t.prefix );
        const bool suf = patternSideUsable( t.suffix );
        RawRef r;
        r.fileId     = m_fileId;
        r.startByte  = ts_node_start_byte( site );
        r.line       = ts_node_start_point( site ).row + 1;
        r.lang       = m_lang;
        r.role       = RefRole::Pattern;
        // "" = a lookup the name-key hop may follow; "t" = a presence test or a store (no call is made through it: still a <pd> clue,
        // never a name-key hop); "w" = too wide: counted, never matched
        r.qualifier  = !( pre || suf ) ? "w" : t.callable ? "" : "t";
        // an unusable side is no constraint: a template `x_{a}.{b}` keeps only its usable prefix; a too-wide one keeps
        // both sides as written (valuerefindex.h counts the members they could name, pattern_too_wide=)
        r.fieldName  = pre || !suf ? t.prefix : std::string();
        r.composeRel = suf || !pre ? t.suffix : std::string();
        r.name       = r.fieldName + "*" + r.composeRel;
        r.recvVar    = ts_node_is_null( recv ) ? std::string() : vrClean( text( recv ) );
        m_out.push_back( std::move( r ) );
    }
    void patternAtCall( TSNode call )
    {
        const TSNode f    = child( call, m_fFunction );
        const TSNode args = child( call, m_fArguments );
        if( ts_node_is_null( f ) || ts_node_is_null( args ) )
        {
            return;
        }
        for( const VrPatternLookup& form : kVrPatternLookups )
        {
            if( form.fam != m_fam || form.computedMember )
            {
                continue;
            }
            TSNode recv {};
            const char* ft = ts_node_type( f );
            if( form.dictGet )
            {
                // `X.__dict__.get( name )`: attribute `get` on attribute `__dict__` of the receiver
                if( !kindIs( ft, "attribute" ) || text( child( f, m_fAttribute ) ) != "get" )
                {
                    continue;
                }
                const TSNode d = child( f, m_fObject );
                if( ts_node_is_null( d ) || !kindIs( ts_node_type( d ), "attribute" ) || text( child( d, m_fAttribute ) ) != form.callee )
                {
                    continue;
                }
                recv = child( d, m_fObject );
            }
            else if( !kindIs( ft, "identifier" ) || text( f ) != form.callee )
            {
                continue;
            }
            // the positional arguments, keyword arguments and comments skipped
            std::vector<TSNode> pos;
            const std::uint32_t cnt = ts_node_named_child_count( args );
            for( std::uint32_t i = 0; i < cnt; ++i )
            {
                const TSNode a = ts_node_named_child( args, i );
                const char*  ak = ts_node_type( a );
                if( !kindIs( ak, "comment" ) && !kindIs( ak, "keyword_argument" ) )
                {
                    pos.push_back( a );
                }
            }
            if( pos.size() <= form.nameArg )
            {
                return;
            }
            if( !form.dictGet )
            {
                recv = pos[0];
            }
            VrTemplate t = templateOf( pos[ form.nameArg ] );
            t.callable   = !form.testOnly;
            emitPattern( call, recv, t );
            return;
        }
    }
    void patternAtSubscript( TSNode sub )
    {
        if( std::ranges::none_of( kVrPatternLookups, [ & ]( const VrPatternLookup& form ) { return form.fam == m_fam && form.computedMember; } ) )
        {
            return;
        }
        // `o[ 'on' + e ] = fn` stores a function under the name (an assignment target, `++`, `delete`): no lookup, so no call
        const TSNode parent = ts_node_parent( sub );
        const char*  pk     = ts_node_is_null( parent ) ? "" : ts_node_type( parent );
        const bool   store  = ( ( kindIs( pk, "assignment_expression" ) || kindIs( pk, "augmented_assignment_expression" ) )
                                && ts_node_eq( child( parent, m_fLeft ), sub ) )
                           || kindIs( pk, "update_expression" )
                           || ( kindIs( pk, "unary_expression" ) && text( child( parent, m_fOperator ) ) == "delete" );
        VrTemplate t = templateOf( child( sub, m_fIndex ) );
        t.callable   = !store;
        emitPattern( sub, child( sub, m_fObject ), t );
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
    const VrSlotLang*              m_slot = nullptr;    // IX-1: this language's slot row (nullptr: no slot capture)
    std::span<const std::string_view> m_regStores;   // REGISTRAR: the language row's container stores (empty: no registrar facts)
    bool                           m_slotByName = false;   // IX1-V2: a MemberCallByName row (Go): the store side only (goValueSlot)
    std::vector<VrStructFields>    m_structs;           // IX-1: this file's struct bodies so far
    std::vector<std::pair<std::string, std::string_view>> m_callableFields;   // IX-1: (struct, function-pointer field) this file declares
    VrAliases                                             m_aliases;          // IX-1: this file's typedef / using alias → struct type key
    VrUsings                                              m_usings;           // FN-SLOT S2 fix 1: this file's `using` declarations and directives so far (C++)
    VrScalarTypedefs                                      m_scalarTypedefs;   // IX-1: this file's typedefs of scalar types
    std::uint32_t                  m_fileId;
    std::string_view               m_src;
    std::vector<RawRef>&           m_out;
    std::vector<VrScope>           m_scopes;
    std::vector<VrAnc>             m_anc;
    std::vector<std::string>       m_fileFed;
    std::vector<RawRef>            m_filePending;
    VrDepthCut                     m_depthCut;
    // call forwarders (model.h kCallForwarders): the sites `f.call( … )` / `f.apply( … )` whose f no enclosing parameter or
    // local declares, and the file's two proofs that a bare f names a function — its function declarations (any depth:
    // a declaration is hoisted and the walk's scopes do not record it) and its file-scope relative imports.
    std::span<const CallForwarder> m_fwd;
    bool                           m_fwdArmed = false;
    std::vector<RawRef>            m_fwdSites;
    std::vector<std::string_view>  m_fnDeclNames;
    std::vector<std::string_view>  m_relImportNames;
    TSFieldId m_fArguments = 0, m_fSource = 0, m_fReceiver = 0;
    TSFieldId m_fScope = 0;   // FN-SLOT S2: a C++ qualified_identifier's scope
    TSFieldId m_fValue = 0, m_fKey = 0, m_fLeft = 0, m_fRight = 0, m_fFunction = 0, m_fName = 0, m_fDeclarator = 0;
    TSFieldId m_fConsequence = 0, m_fAlternative = 0, m_fParameters = 0, m_fParameter = 0, m_fObject = 0, m_fProperty = 0, m_fField = 0;
    TSFieldId m_fArgument = 0, m_fOperand = 0, m_fAttribute = 0, m_fOperator = 0, m_fPattern = 0, m_fDefinition = 0;
    TSFieldId m_fConstructor = 0, m_fType = 0, m_fIndex = 0, m_fSubscript = 0, m_fDesignator = 0, m_fAlias = 0;
};

// Rust's slot records (ingest_rustslots.h, defined after this section).
inline void captureRustSlotRefs( Lang lang, std::uint32_t fileId, std::string_view src, TSNode root, std::vector<RawRef>& refs );

// The pass's entry point: one file's value references and calls-through-a-value, appended to `refs`. Inert on a
// language outside the armed set (C, C++, JavaScript/JSX, TypeScript/TSX, Python, Go; Rust records its slot join's only).
inline void captureValueRefs( Lang lang, std::uint32_t fileId, std::string_view src, TSNode root, std::vector<RawRef>& refs )
{
    const VrFam fam = valueRefFamily( lang );
    if( fam == VrFam::None || ts_node_is_null( root ) )
    {
        return;
    }
    if( fam == VrFam::Rust )
    {
        captureRustSlotRefs( lang, fileId, src, root, refs );   // the slot join's records only (ingest_rustslots.h)
        return;
    }
    PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: value references" );
    ValueRefWalk walk( fam, lang, fileId, src, refs );
    walk.run( root );
}

}   // namespace

}   // namespace rw
