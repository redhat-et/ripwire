#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_sidecap.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_sidecap.h — parse infrastructure + the fused side-capture passes, moved VERBATIM from
// ingest.cpp in the 2026-08-29 split: ParserGuard/grammarAbiOk (the block that sat between the
// metrics and relations families; its only users are here and downstream, so it travels with its
// family), FFI alias capture (pybind11 / extern "C" / ctypes), HTTP-route DEF/USE capture, the
// ABS-3 read/write use-site classifiers, prepareParserFor/parseTree/TreeGuard, the ONE pre-order
// SideFrame stream that fuses every whole-AST side pass (streamSideCaptures + the depth guards),
// captureSideFacts, and captureTagsFacts — the per-file extraction driver the ingest spine calls.
// Same contract as every ingest_*.h: reopens `namespace rw` and the unnamed namespace inside it —
// one TU, one unnamed namespace, internal linkage unchanged, zero new API surface — under the
// RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// One parser, reused across files (single-threaded). Language set per file.
struct ParserGuard
{
    TSParser* p = ts_parser_new();
    ~ParserGuard()
    {
        if( p )
        {
            ts_parser_delete( p );
        }
    }
};

// Verify the grammar's ABI is in range for the linked core. v0.26.9 renamed the
// accessor to ts_language_abi_version; the [MIN_COMPATIBLE, LANGUAGE_VERSION] band is unchanged.
bool grammarAbiOk( const TSLanguage* lang ) noexcept
{
    const uint32_t v = ts_language_abi_version( lang );
    return v >= TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION && v <= TREE_SITTER_LANGUAGE_VERSION;
}

// ── A4-R5 CROSS-LANGUAGE FFI BINDING capture (pybind11 · extern "C" · ctypes handle) ─────────────────
// Walk a C/C++ or Python subtree and emit one BindingAlias per language-binding DECLARATION, so buildGraph
// can add a provenance-tagged FALLBACK edge across the language border. Pure-syntactic, deterministic. The
// pybind pass is GATED on a `pybind11`/`PYBIND11` signal in the file, so a repo without pybind captures
// NOTHING (the whole feature is inert → byte-identical output on any binding-free corpus). JNI needs no
// capture here — buildGraph decodes it straight from `Java_*` def names.
inline std::string ffiUnquote( std::string_view s )   // strip one layer of "..." / '...'; leaves interior verbatim
{
    if( s.size() >= 2 && ( s.front() == '"' || s.front() == '\'' ) && s.back() == s.front() )
    {
        return std::string( s.substr( 1, s.size() - 2 ) );
    }
    return std::string( s );
}

// "A::B::method" → { scope="B", name="method" }; "foo" → { "", "foo" }. Scope is the IMMEDIATE enclosing
// segment (matches buildGraph's canonByName keying); name is the final identifier segment.
inline std::pair<std::string, std::string> ffiSplitScopeName( std::string_view text )
{
    const std::size_t sep = text.rfind( "::" );
    if( sep == std::string_view::npos )
    {
        return { std::string(), finalSegment( text ) };
    }
    return { finalSegment( text.substr( 0, sep ) ), finalSegment( text.substr( sep + 2 ) ) };
}

// One visitor on the shared pre-order stream (streamSideCaptures below). The pass arms only on C++/ObjC/
// Python; the pybind sub-detector stays gated on a cheap file-level signal so ordinary `.def(` calls in
// non-pybind C++ never capture.
struct FfiCtx
{
    std::uint32_t              fileId = 0;
    std::string_view           src;
    std::vector<BindingAlias>* ffis = nullptr;
    bool                       cish      = false;
    bool                       py        = false;
    bool                       hasPybind = false;
};

FfiCtx makeFfiCtx( std::uint32_t fileId, Lang lang, std::string_view src, std::vector<BindingAlias>& ffis )
{
    FfiCtx cx;
    cx.fileId    = fileId;
    cx.src       = src;
    cx.ffis      = &ffis;
    cx.cish      = ( lang == Lang::Cpp || lang == Lang::ObjC );
    cx.py        = ( lang == Lang::Python );
    cx.hasPybind = cx.cish && ( src.find( "pybind11" ) != std::string_view::npos
                             || src.find( "PYBIND11" ) != std::string_view::npos );
    return cx;
}

void ffiVisitNode( FfiCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kFfi );
    const std::uint32_t        fileId    = cx.fileId;
    const std::string_view     src       = cx.src;
    std::vector<BindingAlias>& ffis      = *cx.ffis;
    const bool                 cish      = cx.cish;
    const bool                 py        = cx.py;
    const bool                 hasPybind = cx.hasPybind;

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view { return nodeTextOf( nn, src ); };

        // pybind11:  m.def("alias", &target)  /  cls.def("alias", &Scope::method)  /  .def_static(...)
        if( hasPybind && std::strcmp( t, "call_expression" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "field_expression" ) == 0 )
            {
                const std::string_view meth = nodeSrc( ts_node_child_by_field_name( fn, "field", 5 ) );
                if( meth == "def" || meth == "def_static" )
                {
                    const TSNode args = ts_node_child_by_field_name( n, "arguments", 9 );
                    std::string alias, tgt;
                    const std::uint32_t cc = ts_node_is_null( args ) ? 0 : ts_node_child_count( args );
                    for( std::uint32_t i = 0; i < cc; ++i )
                    {
                        const TSNode c = ts_node_child( args, i );
                        if( !ts_node_is_named( c ) )
                        {
                            continue; // skip '(' ',' ')'
                        }
                        const std::string_view ct = ts_node_type( c );
                        if( alias.empty() && ct == "string_literal" )
                        {
                            alias = ffiUnquote( nodeSrc( c ) );
                        }
                        else if( tgt.empty() )
                        {
                            std::string_view txt = nodeSrc( c );               // `&target` / `&Scope::method`
                            if( !txt.empty() && txt.front() == '&' )
                            {
                                txt.remove_prefix( 1 );
                                while( !txt.empty() && ( txt.front() == ' ' || txt.front() == '\t' ) )
                                {
                                    txt.remove_prefix( 1 );
                                }
                                tgt = std::string( txt );
                            }
                        }
                    }
                    if( !alias.empty() && !tgt.empty() )
                    {
                        auto [ scope, name ] = ffiSplitScopeName( tgt );
                        if( !name.empty() )
                        {
                            ffis.push_back( BindingAlias{ fileId, BindKind::Pybind, false, std::move( alias ), std::move( name ), std::move( scope ) } );
                        }
                    }
                }
            }
        }
        // extern "C": every function DECLARED inside becomes reachable from ctypes/cffi/cgo by its bare name.
        else if( cish && std::strcmp( t, "linkage_specification" ) == 0 )
        {
            // confirm the linkage string is "C" (not "C++") before harvesting.
            bool isC = false;
            const std::uint32_t lc = ts_node_child_count( n );
            for( std::uint32_t i = 0; i < lc; ++i )
            {
                const TSNode c = ts_node_child( n, i );
                if( std::strcmp( ts_node_type( c ), "string_literal" ) == 0 ) { isC = ( ffiUnquote( nodeSrc( c ) ) == "C" ); break; }
            }
            if( isC )
            {
                // inner DFS: collect the identifier of every function_declarator in the linkage body.
                std::vector<TSNode> inner;
                inner.push_back( n );
                while( !inner.empty() )
                {
                    const TSNode m = inner.back();
                    inner.pop_back();
                    if( std::strcmp( ts_node_type( m ), "function_declarator" ) == 0 )
                    {
                        const TSNode decl = ts_node_child_by_field_name( m, "declarator", 10 );
                        if( !ts_node_is_null( decl ) )
                        {
                            const char* dt = ts_node_type( decl );
                            if( std::strcmp( dt, "identifier" ) == 0 || std::strcmp( dt, "field_identifier" ) == 0 )
                            {
                                std::string nm = finalSegment( nodeSrc( decl ) );
                                if( !nm.empty() )
                                {
                                    ffis.push_back( BindingAlias{ fileId, BindKind::ExternC, true, nm, nm, std::string() } );
                                }
                            }
                        }
                    }
                    const std::uint32_t mc = ts_node_child_count( m );
                    for( std::uint32_t i = 0; i < mc; ++i )
                    {
                        inner.push_back( ts_node_child( m, i ) );
                    }
                }
            }
        }
        // Python ctypes handle:  lib = CDLL(...)  /  lib = ctypes.CDLL(...)  /  lib = cdll.LoadLibrary(...)
        else if( py && std::strcmp( t, "assignment" ) == 0 )
        {
            const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
            const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
            if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0
                && !ts_node_is_null( rhs ) && std::strcmp( ts_node_type( rhs ), "call" ) == 0 )
            {
                const std::string_view ftext = nodeSrc( ts_node_child_by_field_name( rhs, "function", 8 ) );
                const std::string      seg   = finalSegment( ftext.substr( 0, ftext.find( '(' ) ) );   // final `.`/`::` segment
                const bool loader = seg == "CDLL" || seg == "WinDLL" || seg == "OleDLL" || seg == "PyDLL"
                                 || seg == "LoadLibrary" || seg == "dlopen";
                if( loader )
                {
                    std::string var( nodeSrc( lhs ) );
                    if( !var.empty() )
                    {
                        ffis.push_back( BindingAlias{ fileId, BindKind::CtypesHandle, true, std::move( var ), std::string(), std::string() } );
                    }
                }
            }
        }
}

// ── B6.3 HTTP-route DEF/USE capture (Express/Fastify · FastAPI/Flask decorators · fetch/axios/requests) ──
// Walk a JS/TS or Python subtree and emit a RouteDef per recognized server-side route registration and a
// RawRouteUse per recognized client-side HTTP call. Pure-syntactic, deterministic, table-driven (the verb
// name → HttpMethod lookup is model.h::kHttpMethodTable, shared by every detector below). Server detectors
// are GATED on a cheap file-level framework signal — the SAME posture as captureFfi's pybind gate above: a
// file that never mentions the framework captures NO route DEF, so the whole feature is inert (byte-
// identical output) on a framework-free corpus. Client detectors need no file gate: `fetch`, `axios.<verb>`,
// `requests.<verb>` are distinctive enough as bare shapes (the object identifier is checked EXACTLY).
// KNOWN LIMITATION (by design, never guessed): a path built from a template literal / f-string / variable
// is NOT a plain "string" node, so it is not captured — only static path literals are detected.

// the first NAMED argument in an `arguments`/`argument_list` node, iff it is a plain "string" literal
// starting with '/' once unquoted — a path-looking literal. "" for anything else (template/f-string,
// identifier, no args): a dynamic path is a deliberate non-detection, never a guess.
inline std::string firstPathStringArg( TSNode argsNode, std::string_view src )
{
    if( ts_node_is_null( argsNode ) || ts_node_named_child_count( argsNode ) == 0 )
    {
        return {};
    }
    const TSNode first = ts_node_named_child( argsNode, 0 );
    if( std::strcmp( ts_node_type( first ), "string" ) != 0 )
    {
        return {}; // template_string/f-string/identifier → skip
    }
    const std::uint32_t a = ts_node_start_byte( first ), b = ts_node_end_byte( first );
    if( a > b || b > src.size() )
    {
        return {};
    }
    std::string path = ffiUnquote( src.substr( a, b - a ) );
    if( path.empty() || path.front() != '/' )
    {
        return {};
    }
    return path;
}

// the LAST named argument's handler name: a bare identifier, or the final `.property` segment of a member
// access (`userController.getUser` → "getUser"). "" for an inline function/arrow expression (anonymous —
// the DEF fact is still recorded; buildGraph just can never attach an edge to it).
inline std::string lastArgHandlerName( TSNode argsNode, std::string_view src )
{
    if( ts_node_is_null( argsNode ) )
    {
        return {};
    }
    const std::uint32_t nc = ts_node_named_child_count( argsNode );
    if( nc == 0 )
    {
        return {};
    }
    const TSNode last = ts_node_named_child( argsNode, nc - 1 );
    const char*  lt   = ts_node_type( last );
    const auto   text = [ & ]( TSNode nn ) -> std::string_view
    {
        const std::uint32_t a = ts_node_start_byte( nn ), b = ts_node_end_byte( nn );
        return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
    };
    if( std::strcmp( lt, "identifier" ) == 0 )
    {
        return finalSegment( text( last ) );
    }
    if( std::strcmp( lt, "member_expression" ) == 0 )
    {
        const TSNode prop = ts_node_child_by_field_name( last, "property", 8 );
        if( !ts_node_is_null( prop ) )
        {
            return finalSegment( text( prop ) );
        }
    }
    return {};   // arrow_function / function_expression / anything else → inline, no name
}

// Flask `methods=[...]` keyword argument: a single-method list resolves to that verb; absent/empty/multi
// ⇒ the caller applies its own default (Flask defaults to GET when `methods=` is absent entirely).
// shared tail of every keyword-argument / options-object method extractor below: a "string" node's
// unquoted, lowercased text, resolved through model.h::kHttpMethodTable. Unknown for anything that isn't
// a plain string literal (never guess).
inline HttpMethod stringNodeToMethod( TSNode strNode, std::string_view src )
{
    if( ts_node_is_null( strNode ) || std::strcmp( ts_node_type( strNode ), "string" ) != 0 )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t a = ts_node_start_byte( strNode ), b = ts_node_end_byte( strNode );
    if( a > b || b > src.size() )
    {
        return HttpMethod::Unknown;
    }
    std::string verb = ffiUnquote( src.substr( a, b - a ) );
    for( char& ch : verb )
    {
        ch = char( std::tolower( static_cast<unsigned char>( ch ) ) );
    }
    return httpMethodFromName( verb );
}

inline HttpMethod pyMethodsKeyword( TSNode argsNode, std::string_view src, bool& hasKeyword )
{
    hasKeyword = false;
    if( ts_node_is_null( argsNode ) )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t nc = ts_node_named_child_count( argsNode );
    for( std::uint32_t i = 0; i < nc; ++i )
    {
        const TSNode c = ts_node_named_child( argsNode, i );
        if( std::strcmp( ts_node_type( c ), "keyword_argument" ) != 0 )
        {
            continue;
        }
        const TSNode nameN = ts_node_child_by_field_name( c, "name", 4 );
        if( ts_node_is_null( nameN ) )
        {
            continue;
        }
        const std::uint32_t na = ts_node_start_byte( nameN ), nb = ts_node_end_byte( nameN );
        if( na > nb || nb > src.size() || src.substr( na, nb - na ) != "methods" )
        {
            continue;
        }
        hasKeyword = true;
        const TSNode valueN = ts_node_child_by_field_name( c, "value", 5 );
        if( ts_node_is_null( valueN ) || std::strcmp( ts_node_type( valueN ), "list" ) != 0 )
        {
            return HttpMethod::Unknown;
        }
        if( ts_node_named_child_count( valueN ) != 1 )
        {
            return HttpMethod::Unknown; // 0 or >1 verbs → ambiguous, path-only match
        }
        return stringNodeToMethod( ts_node_named_child( valueN, 0 ), src );
    }
    return HttpMethod::Unknown;
}

// JS options-object `{ method: 'POST', ... }`: the `method` property's string-literal value, else Unknown
// (never guess — an absent/non-literal method key leaves the USE's method Unknown, which matches ANY DEF
// method per routematch::methodsCompatible in graph.h).
inline HttpMethod jsMethodProperty( TSNode objNode, std::string_view src )
{
    if( ts_node_is_null( objNode ) || std::strcmp( ts_node_type( objNode ), "object" ) != 0 )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t nc = ts_node_named_child_count( objNode );
    for( std::uint32_t i = 0; i < nc; ++i )
    {
        const TSNode c = ts_node_named_child( objNode, i );
        if( std::strcmp( ts_node_type( c ), "pair" ) != 0 )
        {
            continue;
        }
        const TSNode keyN = ts_node_child_by_field_name( c, "key", 3 );
        if( ts_node_is_null( keyN ) )
        {
            continue;
        }
        const char* kt = ts_node_type( keyN );
        const std::uint32_t ka = ts_node_start_byte( keyN ), kb = ts_node_end_byte( keyN );
        if( ka > kb || kb > src.size() )
        {
            continue;
        }
        std::string key;
        if( std::strcmp( kt, "property_identifier" ) == 0 )
        {
            key = std::string( src.substr( ka, kb - ka ) );
        }
        else if( std::strcmp( kt, "string" ) == 0 )
        {
            key = ffiUnquote( src.substr( ka, kb - ka ) );
        }
        else
        {
            continue;
        }
        if( key != "method" )
        {
            continue;
        }
        return stringNodeToMethod( ts_node_child_by_field_name( c, "value", 5 ), src );
    }
    return HttpMethod::Unknown;
}

// One visitor on the shared pre-order stream (streamSideCaptures below). The pass arms only on Python/JS/TS;
// the SERVER detectors stay gated on a file-level framework signal, so a framework-free file still captures
// no route DEF and the whole feature stays byte-inert on a framework-free corpus.
struct RouteCtx
{
    std::uint32_t              fileId = 0;
    std::string_view           src;
    std::vector<RouteDef>*     routeDefs = nullptr;
    std::vector<RawRouteUse>*  routeUses = nullptr;
    bool                       py = false;
    bool                       js = false;
    bool                       pyServerGated = false;
    bool                       jsServerGated = false;
};

RouteCtx makeRouteCtx( std::uint32_t fileId, Lang lang, std::string_view src,
                       std::vector<RouteDef>& routeDefs, std::vector<RawRouteUse>& routeUses )
{
    RouteCtx cx;
    cx.fileId        = fileId;
    cx.src           = src;
    cx.routeDefs     = &routeDefs;
    cx.routeUses     = &routeUses;
    cx.py            = ( lang == Lang::Python );
    cx.js            = ( lang == Lang::TypeScript || lang == Lang::JavaScript );
    cx.pyServerGated = cx.py && ( src.find( "fastapi" ) != std::string_view::npos || src.find( "FastAPI" ) != std::string_view::npos
                                || src.find( "flask" )   != std::string_view::npos || src.find( "Flask" )   != std::string_view::npos );
    cx.jsServerGated = cx.js && ( src.find( "express" ) != std::string_view::npos || src.find( "fastify" ) != std::string_view::npos );
    return cx;
}

void routesVisitNode( RouteCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kRoutes );
    const std::uint32_t        fileId        = cx.fileId;
    const std::string_view     src           = cx.src;
    std::vector<RouteDef>&     routeDefs     = *cx.routeDefs;
    std::vector<RawRouteUse>&  routeUses     = *cx.routeUses;
    const bool                 py            = cx.py;
    const bool                 js            = cx.js;
    const bool                 pyServerGated = cx.pyServerGated;
    const bool                 jsServerGated = cx.jsServerGated;

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view { return nodeTextOf( nn, src ); };

        // Python server: @app.get("/path") / @app.route("/path", methods=[...]) directly above a def.
        if( pyServerGated && std::strcmp( t, "decorated_definition" ) == 0 )
        {
            const TSNode defNode = ts_node_child_by_field_name( n, "definition", 10 );
            std::string  handlerName;
            if( !ts_node_is_null( defNode ) && std::strcmp( ts_node_type( defNode ), "function_definition" ) == 0 )
            {
                const TSNode nameNode = ts_node_child_by_field_name( defNode, "name", 4 );
                if( !ts_node_is_null( nameNode ) )
                {
                    handlerName.assign( nodeSrc( nameNode ) );
                }
            }
            const std::uint32_t cc = ts_node_child_count( n );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode dec = ts_node_child( n, i );
                if( std::strcmp( ts_node_type( dec ), "decorator" ) != 0 )
                {
                    continue;
                }
                const TSNode expr = ts_node_named_child( dec, 0 );
                if( ts_node_is_null( expr ) || std::strcmp( ts_node_type( expr ), "call" ) != 0 )
                {
                    continue;
                }
                const TSNode fn = ts_node_child_by_field_name( expr, "function", 8 );
                if( ts_node_is_null( fn ) || std::strcmp( ts_node_type( fn ), "attribute" ) != 0 )
                {
                    continue;
                }
                const std::string_view attrName = nodeSrc( ts_node_child_by_field_name( fn, "attribute", 9 ) );
                const TSNode argsNode = ts_node_child_by_field_name( expr, "arguments", 9 );
                const std::string path = firstPathStringArg( argsNode, src );
                if( path.empty() )
                {
                    continue;
                }

                HttpMethod method = HttpMethod::Unknown;
                if( attrName == "route" )
                {
                    bool hasKeyword = false;
                    const HttpMethod fromKeyword = pyMethodsKeyword( argsNode, src, hasKeyword );
                    method = hasKeyword ? fromKeyword : HttpMethod::Get;   // Flask default: GET when methods= absent
                }
                else
                {
                    method = httpMethodFromName( attrName );
                    if( method == HttpMethod::Unknown )
                    {
                        continue; // not a recognized verb shortcut (e.g. .on_event)
                    }
                }
                routeDefs.push_back( RouteDef{ fileId, ts_node_start_point( n ).row + 1, method, path, handlerName } );
            }
        }
        // JS/TS: ONE dispatch over every call_expression — client shapes (`fetch`, `axios.<verb>`) are
        // checked FIRST and UNCONDITIONALLY (their callee shape is specific enough to need no file gate),
        // so a server-gated file's axios/fetch calls are NEVER misread as a route DEF; app.get(...)/
        // router.post(...) is the gated FALLBACK, tried only when neither client shape matched. This also
        // fixes the structural trap an `if/else if` split on `jsServerGated` vs `js` would fall into: once
        // the (possibly file-gated) branch claims a call_expression, an else-if chain never lets the OTHER
        // shape see that same node.
        else if( js && std::strcmp( t, "call_expression" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            bool handled = false;

            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "identifier" ) == 0 && nodeSrc( fn ) == "fetch" )
            {
                const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                const std::string path = firstPathStringArg( argsNode, src );
                if( !path.empty() )
                {
                    HttpMethod method = HttpMethod::Get;   // fetch's documented default when no options object
                    if( ts_node_named_child_count( argsNode ) >= 2 )
                    {
                        method = jsMethodProperty( ts_node_named_child( argsNode, 1 ), src );
                    }
                    routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                }
                handled = true;   // "fetch(...)" is never ALSO a server registrar shape
            }
            else if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "member_expression" ) == 0 )
            {
                const TSNode objN = ts_node_child_by_field_name( fn, "object", 6 );
                if( !ts_node_is_null( objN ) && std::strcmp( ts_node_type( objN ), "identifier" ) == 0 && nodeSrc( objN ) == "axios" )
                {
                    const TSNode propN     = ts_node_child_by_field_name( fn, "property", 8 );
                    const HttpMethod method = httpMethodFromName( nodeSrc( propN ) );
                    if( method != HttpMethod::Unknown )
                    {
                        const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                        const std::string path = firstPathStringArg( argsNode, src );
                        if( !path.empty() )
                        {
                            routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                        }
                    }
                    handled = true;   // "axios.<verb>(...)" is never ALSO a server registrar shape
                }
            }

            // JS/TS server FALLBACK: app.get('/path', handler) / router.post('/path', mw, handler) — last
            // arg = handler. Only tried when the callee wasn't already claimed by a client shape above, and
            // only on a file-level framework signal (captureFfi's pybind-gate posture).
            if( !handled && jsServerGated && !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "member_expression" ) == 0 )
            {
                const TSNode propN     = ts_node_child_by_field_name( fn, "property", 8 );
                const HttpMethod method = httpMethodFromName( nodeSrc( propN ) );
                if( method != HttpMethod::Unknown )
                {
                    const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                    const std::string path = firstPathStringArg( argsNode, src );
                    if( !path.empty() )
                    {
                        const std::string handlerName = lastArgHandlerName( argsNode, src );
                        routeDefs.push_back( RouteDef{ fileId, ts_node_start_point( n ).row + 1, method, path, handlerName } );
                    }
                }
            }
        }
        // Python client: requests.get('/path') / requests.post('/path', json=...)
        else if( py && std::strcmp( t, "call" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "attribute" ) == 0 )
            {
                const TSNode objN = ts_node_child_by_field_name( fn, "object", 6 );
                if( !ts_node_is_null( objN ) && std::strcmp( ts_node_type( objN ), "identifier" ) == 0 && nodeSrc( objN ) == "requests" )
                {
                    const TSNode attrN     = ts_node_child_by_field_name( fn, "attribute", 9 );
                    const HttpMethod method = httpMethodFromName( nodeSrc( attrN ) );
                    if( method != HttpMethod::Unknown )
                    {
                        const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                        const std::string path = firstPathStringArg( argsNode, src );
                        if( !path.empty() )
                        {
                            routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                        }
                    }
                }
            }
        }
}

// ── ABS-3 READ / WRITE use-site capture ──────────────────────────────────────────────────────────────
// Walk a subtree and record every IDENTIFIER reference that is a value READ or an assignment WRITE, so the
// use-site index can report read-vs-write per site. The call sites (`f()` / `x.m()`) are already captured
// by the tags query as @reference.call (role=Call); the inheritance/import sites by captureBases/Includes —
// so this walk deliberately EXCLUDES those to avoid double-counting:
//   * the function-position identifier of a call (`foo` in `foo()`, `m` in `x.m()`) → already a Call ref.
//   * a definition's own name / declarator (`x` in `int x;`, `f` in `void f(){}`) → a DEF, not a use.
//   * type positions (`Foo` in `Foo x;`) → captured as inherit/compose where relevant, not a value use.
// WRITE classification (the precision-critical half): an identifier is a Write iff it is the LHS target of
//   an assignment_expression / augmented assignment (C++ `=` `+=` … are all assignment_expression; Python
//   `assignment` / `augmented_assignment`) OR the operand of a `++`/`--` (`update_expression`). Everything
//   else that references a name in a value position is a Read. Pure-syntactic, deterministic.

// two AST nodes refer to the SAME source token iff they span the identical [start,end) byte range. Used to
// test "is THIS identifier the node sitting in field X of its parent" without depending on ts_node_eq.
inline bool sameSpan( TSNode a, TSNode b ) noexcept
{
    return ts_node_start_byte( a ) == ts_node_start_byte( b ) && ts_node_end_byte( a ) == ts_node_end_byte( b );
}

// does `outer`'s [start,end) byte range contain ALL of `inner`? Used by the tags-pass body-climb to tell a
// def that IS an ancestor's signature (outside its body — adopt the ancestor's span) from a def spelled
// INSIDE that body (a nested JS/TS closure — adopting would broadcast the encloser's span onto it).
inline bool spanContains( TSNode outer, TSNode inner ) noexcept
{
    return ts_node_start_byte( inner ) >= ts_node_start_byte( outer ) && ts_node_end_byte( inner ) <= ts_node_end_byte( outer );
}

// is `id` the LHS write-target of its enclosing assignment/update? A4-F24: implements the documented contract
// — `a[i] = …` / `p->f = …` make the BASE OBJECT (`a`, `p`) the target, while the index `i` / member `f` stay
// reads. We climb through subscript/field chains while `id` is the base object (the leading sub-expression
// that shares its parent's start byte — the base always begins at the whole `a[i]`/`p->f` expression's first
// byte; the index/member begin later), then test the assignment/update parent of the climbed node.
// the TAIL both write-target tests share: is `node` (already climbed to the outermost expression it is the
// base of) an update operand, or exactly the `left` side of an assignment?
inline bool isUpdateOrAssignmentTarget( TSNode node ) noexcept
{
    const TSNode parent = ts_node_parent( node );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // C++ `x++` / `--x` and Python aug targets handled via update_expression (the operand is the target).
    if( std::strcmp( pt, "update_expression" ) == 0 )
    {
        return true;
    }

    // direct LHS of an assignment: parent is the assignment node and `node` sits in its `left` field.
    const bool isAssign =    std::strcmp( pt, "assignment_expression" ) == 0       // C++ `=` `+=` `-=` …
                          || std::strcmp( pt, "assignment" ) == 0                  // Python `=`
                          || std::strcmp( pt, "augmented_assignment" ) == 0;       // Python `+=` …
    if( isAssign )
    {
        const TSNode lhs = ts_node_child_by_field_name( parent, "left", 4 );
        return !ts_node_is_null( lhs ) && sameSpan( lhs, node );
    }
    return false;
}

// climb from `node` to the outermost expression it is the BASE of: through subscripts always (`a[i]` — the
// element write is the container's), and through member accesses only when `throughMemberAccess` (`a.b`:
// a bare identifier inherits the whole chain's target-ness; a member access does NOT climb further, because
// in `a.b.c = 1` only `c` is written and `b` is traversed).
inline TSNode outermostBaseOf( TSNode node, bool throughMemberAccess ) noexcept
{
    for( TSNode up = ts_node_parent( node ); !ts_node_is_null( up ); up = ts_node_parent( node ) )
    {
        const char* ut = ts_node_type( up );
        const bool isSubscript = std::strcmp( ut, "subscript_expression" ) == 0 || std::strcmp( ut, "subscript" ) == 0;   // C/C++ · Python `a[i]`
        const bool isMember    = std::strcmp( ut, "field_expression" ) == 0 || std::strcmp( ut, "attribute" ) == 0;       // C/C++ `p->f`,`a.b` · Python `a.b`
        const bool climbs      = isSubscript || ( throughMemberAccess && isMember );
        if( !( climbs && ts_node_start_byte( up ) == ts_node_start_byte( node ) ) )
        {
            break;                              // `node` is the index/member, or the chain ended → stop climbing
        }
        node = up;                              // `node` is the base object → it inherits the whole a[i]/p->f target-ness
    }
    return node;
}

inline bool isWriteTarget( TSNode id ) noexcept
{
    return isUpdateOrAssignmentTarget( outermostBaseOf( id, /*throughMemberAccess=*/ true ) );
}

// is `id` the callee/function-position name of a call (already captured as a Call ref by the tags query)?
inline bool isCallCallee( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // bare call `foo()` — the function field is the identifier itself.
    if( std::strcmp( pt, "call_expression" ) == 0 || std::strcmp( pt, "call" ) == 0 )
    {
        const TSNode fn = ts_node_child_by_field_name( parent, "function", 8 );
        return !ts_node_is_null( fn ) && sameSpan( fn, id );
    }
    // member call `x.m()` / `x->m()` — `id` is the field of a field_expression/attribute that is the
    // function of a call. (The receiver `x` is NOT the callee → still captured as a read below.)
    if( std::strcmp( pt, "field_expression" ) == 0 || std::strcmp( pt, "attribute" ) == 0 )
    {
        const TSNode fieldNode = ts_node_child_by_field_name( parent, "field", 5 );
        const TSNode attrNode  = ts_node_child_by_field_name( parent, "attribute", 9 );
        const bool   isField   = ( !ts_node_is_null( fieldNode ) && sameSpan( fieldNode, id ) )
                              || ( !ts_node_is_null( attrNode )  && sameSpan( attrNode,  id ) );
        if( !isField )
        {
            return false;
        }
        const TSNode gp = ts_node_parent( parent );   // the field-access is the callee only when its parent is a call whose `function` is it
        if( ts_node_is_null( gp ) )
        {
            return false;
        }
        const char* gt = ts_node_type( gp );
        if( std::strcmp( gt, "call_expression" ) != 0 && std::strcmp( gt, "call" ) != 0 )
        {
            return false;
        }
        const TSNode fn = ts_node_child_by_field_name( gp, "function", 8 );
        return !ts_node_is_null( fn ) && sameSpan( fn, parent );
    }
    return false;
}

// A5 shadow fix round: is `id` a DECLARATION-SITE name isNonValueContext's single-`declarator`-field probe
// (arm 2) cannot see? Pre-fix each of these leaked the DECLARED name out as a role="read" site of its own
// declaration (`int& key` param/local, `auto& [key, w]`, `for (int key : arr)`, `[key = expr]`). An
// identifier directly under a reference_declarator or a structured_binding_declarator is ALWAYS a declared
// name (value expressions live under other node types); a range-for's is its `declarator` field; an
// init-capture's is its FIRST named child (the value side of `[a = b]` stays a genuine read of b).
// `variadic_declarator` (`Ts... key`) and `attributed_declarator` (`int key [[maybe_unused]]`) join the
// unconditional arm for the same grammar reason: each holds its inner declarator as an UNNAMED child, so
// arm 2's `declarator`-field probe returns null and sees nothing. Their only bare-identifier child is the
// declared name — a pack's attributes are `attribute_declaration` nodes, never loose identifiers.
// NOT fixable here, and deliberately left listed: `int (key);` — the most-vexing parse, which tree-sitter
// resolves to an `argument_list`, the same node every genuine call ARGUMENT lives under. Suppressing that
// parent would delete real reads corpus-wide to chase a shape that is vanishingly rare in real source.
// Iteration 4 adds the shape arm 2 looks straight at and still misses: a `declaration` carries one
// `declarator` FIELD PER DECLARED NAME, so ts_node_child_by_field_name — which returns the FIRST — sees
// `a` in `int a, key;` and never `key`; a bare `int key;` it misses outright, the parent type not being in
// arm 2's list at all. Iterations 1-3 could not observe either, because the block-start span suppressed the
// declaration line along with the rest of the block; declaration-point spans stop covering it.
inline bool isDeclSiteName( TSNode id, TSNode parent, const char* pt ) noexcept
{
    if( std::strcmp( pt, "reference_declarator" ) == 0 || std::strcmp( pt, "structured_binding_declarator" ) == 0
        || std::strcmp( pt, "variadic_declarator" ) == 0 || std::strcmp( pt, "attributed_declarator" ) == 0 )
    {
        return true;
    }
    if( std::strcmp( pt, "declaration" ) == 0 )
    {
        const std::uint32_t cc = ts_node_child_count( parent );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const char* fieldName = ts_node_field_name_for_child( parent, i );
            if( fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0 && sameSpan( ts_node_child( parent, i ), id ) )
            {
                return true;
            }
        }
        return false;
    }
    if( std::strcmp( pt, "for_range_loop" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        return !ts_node_is_null( decl ) && sameSpan( decl, id );
    }
    if( std::strcmp( pt, "lambda_capture_initializer" ) == 0 )
    {
        return ts_node_named_child_count( parent ) > 0 && sameSpan( ts_node_named_child( parent, 0 ), id );
    }
    return false;
}

// is `id` in a NON-VALUE context — a name being DEFINED, DECLARED, or part of a qualified/scoped name —
// so it must NOT be counted as a read/write use-site? (Definition NAMES are captured by the tags query;
// qualified-name segments and declarators are not value uses.) Conservative by construction: when in doubt
// we EXCLUDE rather than mislabel — a missed read is far better than reporting a def's own name as a "read".
inline bool isNonValueContext( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // (1) part of a qualified / scoped NAME (`A::process` def name, `A::b()` qualified call name, `ns::T`
    //     type, `A::kConst` qualified value): the segment is not a plain value identifier. Calls/defs of
    //     this shape are captured by the tags query; qualified value reads are intentionally out of scope.
    if( std::strcmp( pt, "qualified_identifier" ) == 0 || std::strcmp( pt, "scoped_identifier" ) == 0 || std::strcmp( pt, "scoped_type_identifier" ) == 0 || std::strcmp( pt, "qualified_type_identifier" ) == 0 || std::strcmp( pt, "template_function" ) == 0 || std::strcmp( pt, "template_type" ) == 0 )
    {
        return true;
    }

    // (2) a declarator's NAME (a DEF/declaration, not a use): `int x;`, `void f()`, `Foo* p`, parameters.
    // `optional_parameter_declaration` is `parameter_declaration`'s DEFAULTED sibling (`int x = 0`) and
    // carries the same `declarator` field — probing the field, not the node type, is what keeps a default
    // VALUE that names a symbol (`int v = probe()`, a different field) a genuine use.
    if(    std::strcmp( pt, "function_declarator" ) == 0 || std::strcmp( pt, "init_declarator" ) == 0
        || std::strcmp( pt, "parameter_declaration" ) == 0 || std::strcmp( pt, "pointer_declarator" ) == 0
        || std::strcmp( pt, "reference_declarator" ) == 0  || std::strcmp( pt, "array_declarator" ) == 0
        || std::strcmp( pt, "optional_parameter_declaration" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        if( !ts_node_is_null( decl ) && sameSpan( decl, id ) )
        {
            return true;
        }
    }
    // (2b) A5 shadow fix round: declaration-site names the field probe above cannot see (isDeclSiteName).
    if( isDeclSiteName( id, parent, pt ) )
    {
        return true;
    }
    // (3) Python function / parameter NAME field (a DEF/param, not a use).
    if( std::strcmp( pt, "function_definition" ) == 0 || std::strcmp( pt, "parameters" ) == 0
        || std::strcmp( pt, "typed_parameter" ) == 0 || std::strcmp( pt, "default_parameter" ) == 0
        || std::strcmp( pt, "lambda_parameters" ) == 0 )
    {
        const TSNode nm = ts_node_child_by_field_name( parent, "name", 4 );
        if( ( !ts_node_is_null( nm ) && sameSpan( nm, id ) ) || std::strcmp( pt, "parameters" ) == 0 || std::strcmp( pt, "lambda_parameters" ) == 0 )
        {
            return true;   // every direct child of a parameter list is a param NAME, not a use
        }
    }
    return false;
}

// One visitor on the shared pre-order stream (streamSideCaptures below). It keeps its OWN 512-node depth
// cap — twice the other passes' — which the shared stream honours per visitor: past 256 the FFI/route/bind
// visitors stop being called while this one keeps receiving nodes, exactly as their separate walks behaved.
struct UseCtx
{
    std::uint32_t        fileId = 0;
    Lang                 lang {};
    std::string_view     src;
    std::vector<RawRef>* refs = nullptr;
};

// A bare TYPE-MENTION node — the RefRole::Type accept set. DELIBERATELY NARROWER than isBaseTypeNode
// above, which was written for base clauses and is a superset that would misfire here:
//   * `identifier` is in that table for TS/Python base clauses; here it is already the VALUE path below,
//     and accepting it twice would re-label every ordinary read as a type.
//   * `qualified_identifier` / `scoped_type_identifier` / `generic_type` / `generic_name` /
//     `qualified_name` are CONTAINERS whose own name segment is a `type_identifier` child. Accepting the
//     container as well would emit two refs for one mention, and `qualified_name` in particular is C#'s
//     dotted-value node — a value read wearing a type node's name.
// So: the leaf node that actually spells a type, and nothing else. `std::vector<Widget>` yields exactly
// one Type ref (`Widget`); `vector` is skipped by isNonValueContext's qualified-segment rule, the same
// rule that already keeps a qualified VALUE read out of the index. The value-uses pass is armed for
// C++/ObjC/Python only (see streamSideCaptures' arming), and Python spells its annotations with plain
// `identifier`, so `user_type` (Swift) / `type_identifier` (Rust, Java, TS) are unreachable today and are
// NOT listed — a kind in this table that no armed language can produce is a claim the gate cannot check.
inline bool isTypeMentionNode( const char* nt ) noexcept
{
    static const char* const kTypeMentionKinds[] = {
        "type_identifier",   // C/C++/ObjC — the leaf node that names a class, struct, enum or typedef
    };
    for( const char* k : kTypeMentionKinds )
    {
        if( std::strcmp( nt, k ) == 0 )
        {
            return true;
        }
    }
    return false;
}

// A type-name node that is NOT a mention of some other definition. Three shapes, and each would be a
// distinct kind of lie in the use-site index:
//   (a) the NAME of a type DEFINITION (`struct Widget {…}`, `enum class E : int`, `using A = B;`,
//       `typedef struct X Y;`) — a definition is not a use of itself, and emitting one would give every
//       indexed type a permanent self-reference and inflate every blast radius by exactly one row.
//   (b) a BASE CLAUSE — that position already has its own role (RefRole::Extends, emitted by
//       captureBases), so a second row would double-count the one relation the tool already models.
//   (c) a TYPE PARAMETER's own name (`template< typename T >`) — T is being declared here, not named.
inline bool isTypeDeclarationSite( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // (b) base clause — RefRole::Extends owns this position.
    if( std::strcmp( pt, "base_class_clause" ) == 0 )
    {
        return true;
    }

    // (c) a type parameter DECLARES its name.
    if(    std::strcmp( pt, "type_parameter_declaration" ) == 0 || std::strcmp( pt, "variadic_type_parameter_declaration" ) == 0
        || std::strcmp( pt, "optional_type_parameter_declaration" ) == 0 )
    {
        return true;
    }

    // (a) the `name` field of a type definition — probe the FIELD, not the node type, so a base name or a
    // member type sitting under the same parent kind stays a genuine mention.
    static const char* const kTypeDefParents[] = {
        "struct_specifier", "class_specifier", "union_specifier", "enum_specifier", "alias_declaration", "concept_definition",
    };
    for( const char* k : kTypeDefParents )
    {
        if( std::strcmp( pt, k ) == 0 )
        {
            const TSNode nm = ts_node_child_by_field_name( parent, "name", 4 );
            if( !ts_node_is_null( nm ) && sameSpan( nm, id ) )
            {
                return true;
            }
        }
    }
    // `typedef struct X Y;` — Y is the DECLARATOR field and is the new name; X keeps its mention.
    if( std::strcmp( pt, "type_definition" ) == 0 )
    {
        const TSNode dc = ts_node_child_by_field_name( parent, "declarator", 10 );
        if( !ts_node_is_null( dc ) && sameSpan( dc, id ) )
        {
            return true;
        }
    }
    return false;
}

// member-variable round (card A3): is `id` the FIELD half of a member access — C/C++ `a.f` / `p->f`
// (field_expression, `.field`), Python `o.f` (attribute, `.attribute`)? Returns the access node, or a null
// node. The receiver half (`a`, `p`, `o`) is NOT this shape and keeps its bare-identifier treatment.
inline TSNode memberAccessOfField( TSNode id, Lang lang ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) || !isMemberAccessNode( ts_node_type( parent ), lang ) )
    {
        return TSNode{};
    }
    const TSNode fieldNode = memberAccessField( parent, lang );
    return ( !ts_node_is_null( fieldNode ) && sameSpan( fieldNode, id ) ) ? parent : TSNode{};
}

// The member twin of isWriteTarget: the ACCESS node (`a.f`), climbing only through subscripts (`a.buf[i] = v`
// writes the member array, the same rule the bare form applies to `arr[i] = v`), is an update operand or the
// LEFT side of an assignment. Deliberately NOT climbed through a further member access: in `a.b.c = 1` only
// `c` is written and `b` is traversed — a READ. Pass-by-non-const-reference (`mutate( a.f )`) and address-of
// (`&a.f`) are reads here; a write through either is a disclosed miss, never a claim.
inline bool isMemberWriteTarget( TSNode access ) noexcept
{
    return isUpdateOrAssignmentTarget( outermostBaseOf( access, /*throughMemberAccess=*/ false ) );
}

// What the value-use visitor accepts at one node, decided ONCE: `accept` false ⇒ nothing to record; else
// `typeMention` marks the role=Type set and `access` is the member-access node when the identifier is the
// FIELD half of `a.f` / `p->f` / Python `o.f` (null for a bare identifier).
struct UseSiteShape
{
    bool   accept      = false;
    bool   typeMention = false;
    TSNode access {};
};

inline UseSiteShape classifyUseSite( TSNode n, const char* t, Lang lang ) noexcept
{
    UseSiteShape shape;
    shape.typeMention = isTypeMentionNode( t );
    const bool isFieldIdent = std::strcmp( t, "field_identifier" ) == 0;
    if( !shape.typeMention && !isFieldIdent && std::strcmp( t, "identifier" ) != 0 )
    {
        return shape;
    }
    if( isCallCallee( n ) || isNonValueContext( n ) || ( shape.typeMention && isTypeDeclarationSite( n ) ) )
    {
        return shape;
    }
    shape.access = shape.typeMention ? TSNode{} : memberAccessOfField( n, lang );
    shape.accept = !isFieldIdent || !ts_node_is_null( shape.access );   // a field_identifier outside a member access is a declaration site
    return shape;
}

// The receiver shape of a member-access use, stamped on the ref so graph.h collectFieldUseSites can resolve
// the site to an OWNER: recv=ThisObj/NamedVar/FieldOfThis/FieldOfVar — on a Read/Write ref, recv != None
// MEANS "a member access", and FieldOfVar with an empty recvVar means the receiver was too rich to classify.
inline void stampMemberReceiver( RawRef& r, TSNode access, Lang lang, std::string_view src )
{
    const TSNode recvNode = memberAccessReceiver( access, lang );
    RecvShape    rs       = ts_node_is_null( recvNode ) ? RecvShape{} : classifyReceiver( recvNode, lang, src, /*allowChain=*/ true );
    r.recv      = rs.kind == RecvKind::None ? RecvKind::FieldOfVar : rs.kind;   // a member access is never a bare name
    r.recvVar   = std::move( rs.var );
    r.fieldName = std::move( rs.field );
}

void usesVisitNode( UseCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kUses );
    // Three accept sets, one visitor. (1) bare value identifiers (C++ `identifier`, Python `identifier`) →
    // role=Read/Write, unchanged. (2) the FIELD half of a non-call member access (`obj.field` / `p->field` /
    // Python `o.field` — C/C++ `field_identifier`, Python `identifier` under an `attribute`) → role=Read/Write
    // with the RECEIVER shape recorded on the ref (recv=ThisObj/NamedVar/FieldOfThis/FieldOfVar — on a
    // Read/Write ref, recv != None MEANS "a member access", and FieldOfVar with an empty recvVar means the
    // receiver was too rich to classify), so graph.h collectFieldUseSites can resolve the site to an OWNER
    // instead of matching the bare name (the member-variable round, card A3). A field_identifier anywhere else
    // (a declarator, a designated initializer) is a declaration, never a use. (3) bare TYPE mentions
    // (`type_identifier`) → role=Type: a type named in a signature, a declaration or a template argument IS
    // a dependency on that type, and it was captured by NOTHING before this. All three roles stay OUT of the
    // call graph (buildGraph admits Call and Macro only), so the default ranked map is byte-identical either way.
    const UseSiteShape shape = classifyUseSite( n, t, cx.lang );
    if( !shape.accept )
    {
        return;
    }
    const std::string_view src      = cx.src;
    const std::uint32_t    a        = ts_node_start_byte( n ), b = ts_node_end_byte( n );
    const bool             isMember = !ts_node_is_null( shape.access );
    if( a < b && b <= src.size() )
    {
        RawRef r;
        r.fileId    = cx.fileId;
        r.startByte = a;
        r.line      = ts_node_start_point( n ).row + 1;
        r.lang      = cx.lang;
        const bool isWrite = isMember ? isMemberWriteTarget( shape.access ) : isWriteTarget( n );
        r.role      = shape.typeMention ? RefRole::Type : ( isWrite ? RefRole::Write : RefRole::Read );
        r.name      = finalSegment( src.substr( a, b - a ) );   // bare identifier → already final segment
        if( isMember )
        {
            stampMemberReceiver( r, shape.access, cx.lang, src );
        }
        cx.refs->push_back( std::move( r ) );
    }
}

bool prepareParserFor( TSParser* parser, const LangEntry& le )
{
    const TSLanguage* lang = le.grammar();
    if( lang == nullptr )
    {
        return false;
    }

    if( !ts_parser_set_language( parser, lang ) || !grammarAbiOk( lang ) )
    {
        // never emit a silently-empty tree — say which language we dropped.
        std::fprintf( stderr, "[ripwire] grammar ABI mismatch or set_language failed for %s — skipping language\n",
                      std::string( le.querySub ).c_str() );
        return false;
    }
    return true;
}

TSTree* parseTree( TSParser* parser, std::string_view src )
{
    TSTree* tree = nullptr;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: tree-sitter parse" );
        tree = ts_parser_parse_string( parser, nullptr, src.data(), static_cast<uint32_t>( src.size() ) );
    }
    return tree;
}

struct TreeGuard
{
    TSTree* tree = nullptr;

    explicit TreeGuard( TSTree* treeIn = nullptr ) noexcept : tree( treeIn ) {}
    TreeGuard( const TreeGuard& ) = delete;
    TreeGuard& operator=( const TreeGuard& ) = delete;
    TreeGuard( TreeGuard&& other ) noexcept : tree( other.tree ) { other.tree = nullptr; }
    TreeGuard& operator=( TreeGuard&& other ) noexcept
    {
        if( this != &other )
        {
            if( tree != nullptr )
            {
                ts_tree_delete( tree );
            }
            tree = other.tree;
            other.tree = nullptr;
        }
        return *this;
    }
    ~TreeGuard()
    {
        if( tree != nullptr )
        {
            ts_tree_delete( tree );
        }
    }
    TSTree* get() const noexcept { return tree; }
    TSTree* release() noexcept
    {
        TSTree* out = tree;
        tree = nullptr;
        return out;
    }
};

// ── ONE pre-order stream for every whole-AST side-capture pass ────────────────────────────────────────
// FFI, routes, Rust impls, bindings and value-uses each used to run their OWN iterative pre-order walk of
// the same tree, back to back. Measured with a per-pass node-pop probe on a 1659-file ObjC++/C++ corpus:
// 95.0% of files ran captureFfi AND captureBindings, 93.4% ran three passes, and every node was streamed
// 2.01x on a default run / 3.01x with --uses armed. That re-streaming — not the per-node matching, which
// is a strcmp or two — is why the `side captures` profile scope showed ~2x tree-sitter's L1D MPKI and ~2x
// its LLC misses on half the instructions. The passes now share one stream; the per-node work is unchanged.
//
// ENTRY RULES. This is the union of what the fused passes need, and it is exactly "every node", because
// FFI / bindings / value-uses each already descended unconditionally. captureIncludes is deliberately NOT
// fused: it enters only ALLOWLISTED import containers (isImportContainer) and cost 59 node pops per file
// against ~7,800 for a full walk — 0.4% of all pops. Folding it in would either make it visit ~130x more
// nodes or force a per-frame "still inside an allowlisted chain" bit, and its restricted entry set is what
// DEFINES which directives it captures. It keeps its own walk.
//
// DEPTH. Each pass's own pathological-AST cap survives as a per-visitor `maxDepth`: past its cap a visitor
// simply stops being called while the others keep descending — which is what that pass's own `continue`
// did (it skipped the node AND its subtree, and depth only grows). The stream descends while ANY armed
// visitor still wants nodes, so the heap stack's high-water mark is max(caps) — 512 with --uses armed,
// exactly what captureUses' own walk already reached, and 256 otherwise. No frame got fatter either: the
// fused frame is one TSNode + one depth, the same shape (and the same 40 bytes) as each pass's old frame.
//
// EMISSION ORDER. Every fused pass appends to its OWN output vector, so within a vector the order is that
// pass's own node order — byte-identical to running the passes back to back. `refs` is the one vector two
// fused passes could share (Rust impls and value-uses), and they are disjoint by language (Rust vs
// C++/ObjC/Python), so at most one is ever armed; sideArmsAreOrderSafe pins that invariant. Visitors are
// still invoked in the ORIGINAL pass order at each node, so the reading order matches the old call order.
// depth is 32-bit, not the 16-bit each pass used to carry: same 40 bytes after padding either way, and a
// tree deeper than 65535 can no longer WRAP the counter back under a cap and re-enable a visitor that
// should have stopped. Unreachable on a <= 1 MB file, but the old shape was the fragile one.
struct SideFrame
{
    TSNode        node;
    std::uint32_t depth;
};
static_assert( sizeof( SideFrame ) == sizeof( TSNode ) + 8, "the fused frame must not outgrow one node + a depth" );

constexpr std::uint32_t kSideDepthStd       = 256;           // FFI / routes / bindings — their own guard
constexpr std::uint32_t kSideDepthUses      = 512;           // value-uses — twice the others, as it always was
constexpr std::uint32_t kSideDepthUnbounded = 0xFFFFFFFFu;   // Rust impls — that pass never had a cap

// The armed set for one file. A pass whose context pointer is null is not armed and costs one predictable
// branch per node; that is what keeps a file-level gate from turning into an always-on walk.
struct SideArms
{
    FfiCtx*      ffi   = nullptr;
    RouteCtx*    route = nullptr;
    RustImplCtx* rust  = nullptr;
    BindCtx*     bind  = nullptr;
    UseCtx*      uses  = nullptr;
};

// see EMISSION ORDER above: the two passes that write `refs` must never be armed together.
inline bool sideArmsAreOrderSafe( const SideArms& arms ) noexcept
{
    return arms.rust == nullptr || arms.uses == nullptr;
}

void streamSideCaptures( TSNode root, const SideArms& arms )
{
    VERIFY( sideArmsAreOrderSafe( arms ) );

    std::uint32_t deepest = 0;
    if( arms.ffi   != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.route != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.bind  != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.uses  != nullptr ) { deepest = std::max( deepest, kSideDepthUses ); }
    if( arms.rust  != nullptr ) { deepest = kSideDepthUnbounded; }
    if( deepest == 0 )
    {
        return;   // nothing armed — do not touch the tree at all
    }

    // Iterative, never recursive: worker threads get 512 KB stacks on macOS and a deep AST overflows the
    // call stack well inside any depth guard. Children are pushed in REVERSE so pops preserve left-to-right
    // source order — the determinism contract is byte-identity, and an order that depended on the walk
    // shape would break it.
    std::vector<SideFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
        const SideFrame frame = stack.back();
        stack.pop_back();
        FUSEPROBE_POP();
        if( frame.depth > deepest )
        {
            continue;   // past every armed visitor's cap — this subtree is nobody's business
        }
        const TSNode n = frame.node;
        const char*  t = ts_node_type( n );

        // original pass order: FFI, routes, Rust impls, bindings, value-uses.
        if( arms.ffi   != nullptr && frame.depth <= kSideDepthStd )  { ffiVisitNode   ( *arms.ffi,   n, t ); }
        if( arms.route != nullptr && frame.depth <= kSideDepthStd )  { routesVisitNode( *arms.route, n, t ); }
        if( arms.rust  != nullptr )                                  { rustImplVisitNode( *arms.rust, n, t ); }
        if( arms.bind  != nullptr && frame.depth <= kSideDepthStd )  { bindsVisitNode ( *arms.bind,  n, t ); }
        if( arms.uses  != nullptr && frame.depth <= kSideDepthUses ) { usesVisitNode  ( *arms.uses,  n, t ); }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], frame.depth + 1 } );
        }
    }
}

void captureSideFacts( const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawRef>& refs, std::vector<Include>& incs, std::vector<RawBind>& binds,
                       std::vector<BindingAlias>& ffis, std::vector<RouteDef>& routeDefs,
                       std::vector<RawRouteUse>& routeUses, bool captureValueUses )
{
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: side captures" );

#ifdef RIPWIRE_FUSE_PROBE
        std::uint64_t probeBefore[ fuseprobe::kPassCount ];
        for( int p = 0; p < fuseprobe::kPassCount; ++p )
        {
            probeBefore[ p ] = fuseprobe::tlNodes[ p ];
        }
#endif

        captureIncludes( root, le.lang, fileId, src, incs, refs );   // physical deps + ABS-3 import-role use-sites

        // A4-R5: cross-language FFI binding declarations (pybind11 / extern "C" / ctypes handle). Inert on a
        // binding-free file (pybind gated on a file signal; extern-C/ctypes only fire on their exact shapes).
        FfiCtx   ffiCtx   = makeFfiCtx( fileId, le.lang, src, ffis );

        // B6.3: HTTP-route DEF/USE facts (Express/Fastify · FastAPI/Flask · fetch/axios/requests). Server
        // detectors gated on a file-level framework signal; inert on a framework-free / non-JS/Python file.
        RouteCtx routeCtx = makeRouteCtx( fileId, le.lang, src, routeDefs, routeUses );

        // Rust IS-A: `impl Trait for T` is a top-level impl_item (sibling of the struct), unreachable from the
        // struct's def-walk. Derived type name rides `qualifier` (name-resolved in buildGraph).
        RustImplCtx rustCtx { fileId, src, &refs };

        // P2-D Rule 2: local var→type bindings (`Foo x;`), for receiver-variable narrowing. C++/ObjC/Python/TS
        // (the languages whose receiver shape `receiverOf` captures as a recvVar) — others have no consumer yet.
        // L3 adds Lang::C for the fn-pointer/callback var→function capture only: the Rule-2 branches inside
        // gate themselves on Cpp/ObjC/Python/TS, so type narrowing is byte-identical on C files.
        BindCtx bindCtx;
        bindCtx.fileId    = fileId;
        bindCtx.lang      = le.lang;
        bindCtx.src       = src;
        bindCtx.binds     = &binds;
        bindCtx.cFamilyFn = ( le.lang == Lang::Cpp || le.lang == Lang::C || le.lang == Lang::ObjC );

        // ABS-3: read/write use-site capture (bare value identifiers + assignment targets). C++/ObjC/Python —
        // the languages whose assignment/update grammar shapes isWriteTarget knows. role=Read/Write refs NEVER
        // enter the call graph (buildGraph skips role != Call), so PageRank and the default map are unchanged.
        UseCtx useCtx { fileId, le.lang, src, &refs };

        SideArms arms;
        if( ffiCtx.cish || ffiCtx.py )
        {
            arms.ffi = &ffiCtx;
        }
        if( routeCtx.py || routeCtx.js )
        {
            arms.route = &routeCtx;
        }
        if( le.lang == Lang::Rust )
        {
            arms.rust = &rustCtx;
        }
        if( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python || le.lang == Lang::TypeScript
            || le.lang == Lang::C )
        {
            arms.bind = &bindCtx;
        }
        if( captureValueUses && ( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python ) )
        {
            arms.uses = &useCtx;
        }

        streamSideCaptures( root, arms );

        if( arms.bind != nullptr )
        {
            bindsFinalize( bindCtx );   // L3 noise gates + clobber sweep — the tail of the old captureBindings
        }

#ifdef RIPWIRE_FUSE_PROBE
        {
            int           sawNode = 0;
            std::uint64_t maxPass = 0;
            for( int p = 0; p < fuseprobe::kPassCount; ++p )
            {
                const std::uint64_t d = fuseprobe::tlNodes[ p ] - probeBefore[ p ];
                if( d != 0 )
                {
                    ++sawNode;
                    fuseprobe::gFiles[ p ].fetch_add( 1, std::memory_order_relaxed );
                }
                if( d > maxPass )
                {
                    maxPass = d;
                }
                fuseprobe::gNodes[ p ].fetch_add( d, std::memory_order_relaxed );
            }
            fuseprobe::gNodesMaxPass.fetch_add( maxPass, std::memory_order_relaxed );
            fuseprobe::gHist[ sawNode ].fetch_add( 1, std::memory_order_relaxed );
            fuseprobe::gFilesTotal.fetch_add( 1, std::memory_order_relaxed );
        }
#endif
    }
}

// member-variable round (card A3): the FIELD post-pass over ONE file's freshly captured defs (defs[first..)).
// Two rules, both applied after the match loop so the loop itself gains no branch:
//   * a field with no owner NAME (an anonymous struct/union member, or a `.c` file — Lang::C computes no
//     scope) has no `Owner.field` address → dropped, disclosed in the member legend (C fields in `.h` headers
//     extract under the C++ grammar and keep their owner);
//   * Python: every `self.x = …` fires the pattern, and ONE symbol per (class, name) survives — the lowest
//     nameByte is the definition, the rest are role="write" use-sites. Decided by a sorted key set so the
//     survivor never depends on the cursor's match order.
// Non-field defs are untouched and keep their relative order (a stable partition, not a sort).
inline void foldFieldDefs( std::vector<RawDef>& defs, std::size_t first, Lang lang )
{
    std::vector<std::string> seenPyField;   // "scope\x1fname" of every Python field kept so far, sorted
    std::size_t write = first;
    for( std::size_t read = first; read < defs.size(); ++read )
    {
        RawDef& d = defs[ read ];
        bool keep = d.kind != SymKind::Field || !d.scope.empty();
        if( keep && d.kind == SymKind::Field && lang == Lang::Python )
        {
            const std::string key = d.scope + '\x1f' + d.name;
            const auto        at  = std::lower_bound( seenPyField.begin(), seenPyField.end(), key );
            keep = at == seenPyField.end() || *at != key;
            if( keep )
            {
                seenPyField.insert( at, key );
            }
        }
        if( keep )
        {
            if( write != read )
            {
                defs[ write ] = std::move( d );
            }
            ++write;
        }
    }
    defs.resize( write );
}

void captureTagsFacts( TSQueryCursor* cursor, const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    if( cursor == nullptr )
    {
        return;
    }

    TSQuery* query = compiledQueryFor( le );   // shared immutable query, compiled once per grammar (pre-warmed) — do NOT delete
    if( query == nullptr )
    {
        return;
    }

    const std::size_t firstDefOfFile = defs.size();   // member-variable round: foldFieldDefs' window (below)

    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: tags query exec+captures" );
        ts_query_cursor_exec( cursor, query, root );

        TSQueryMatch match;
        while( ts_query_cursor_next_match( cursor, &match ) )
        {
            // A tags pattern yields one @definition/@reference node + a child @name.
            // Walk this match's captures: remember the role node + the name text.
            SymKind          kind     = SymKind::Other;
            bool             isDef    = false;
            bool             isRef    = false;
            std::string_view defCapSv;   // the @definition capture's name — dropGatedCapture keys the constant/cjsexport/protomethod gates on it
            std::string_view refCapSv;   // the @reference capture's name — "reference.import" routes the using-declaration role (r9 loss bucket 1)
            TSNode           roleNode {};
            bool             haveRole = false;
            std::string_view nameTxt;
            uint32_t         nameByte = 0;
            uint32_t         nameRow  = 0;   // 0-based row of the @name identifier
            bool             haveName = false;
            TSNode           nameNode {};    // the @name identifier node — for C++ scope/qualifier (E#4)

            for( uint16_t ci = 0; ci < match.capture_count; ++ci )
            {
                const TSQueryCapture& cap = match.captures[ ci ];

                uint32_t    nameLen = 0;
                const char* capName = ts_query_capture_name_for_id( query, cap.index, &nameLen );
                const std::string_view capSv( capName, nameLen );

                SymKind k = SymKind::Other;
                switch( roleOf( capSv, k ) )
                {
                    case CapRole::Def:
                    {
                        isDef          = true;
                        kind           = k;
                        defCapSv       = capSv;
                        roleNode       = cap.node;
                        haveRole       = true;
                    }
                    break;

                    case CapRole::Ref:
                    {
                        isRef    = true;
                        refCapSv = capSv;
                        roleNode = cap.node;
                        haveRole = true;
                    }
                    break;

                    case CapRole::NameOnly:
                    {
                        const uint32_t a = ts_node_start_byte( cap.node );
                        uint32_t       b = ts_node_end_byte( cap.node );

                        // A C++ conversion operator's declarator is an `operator_cast` node whose text spans
                        // the WHOLE `operator <type>() const` (the tags query captures the declarator itself —
                        // there is no sub-node spanning just `operator bool`). Trim the name's end to the end of
                        // the `type` field so the symbol name is `operator bool` / `operator MyType`, not the
                        // param list. Symbolic ops (operator==/[]/()) go through operator_name and are untouched —
                        // trimming at `(` there would wrongly cut `operator()`, so this is operator_cast-only.
                        if( std::strcmp( ts_node_type( cap.node ), "operator_cast" ) == 0 )
                        {
                            const TSNode typeNode = ts_node_child_by_field_name( cap.node, "type", 4 );
                            if( !ts_node_is_null( typeNode ) )
                            {
                                const uint32_t typeEnd = ts_node_end_byte( typeNode );
                                if( typeEnd > a && typeEnd <= b )
                                {
                                    b = typeEnd;
                                }
                            }
                        }

                        if( b <= src.size() && a <= b )
                        {
                            nameTxt  = src.substr( a, b - a );
                            nameByte = a;
                            nameRow  = ts_node_start_point( cap.node ).row;
                            nameNode = cap.node;
                            haveName = true;
                        }
                    }
                    break;

                    case CapRole::Ignore:
                    break;
                }
            }

            if( !haveName )
            {
                continue;
            }

            // Some patterns (e.g. a bare (identifier) @name) carry no @definition/@reference
            // wrapper. Treat a wrapper-less @name as a reference fallback only when the pattern
            // had a role; otherwise skip (avoids turning every identifier into an edge).
            if( !haveRole )
            {
                continue;
            }

            // C1 (memgraph F1) — see cppDefNameReseat. A null node is "nothing to re-seat".
            const auto [ reNode, reTxt, reByte, reRow ] = cppDefNameReseat( isDef && le.lang == Lang::Cpp, nameNode, src );
            if( !ts_node_is_null( reNode ) )
            {
                nameNode = reNode;  nameTxt = reTxt;  nameByte = reByte;  nameRow = reRow;
            }

            // F5: drop Swift function-local `let`/`var` bindings — they are not module symbols and, left in,
            // they steal the enclosing function's call edges (the last local binding above the call sites
            // becomes the nearest enclosing symbol). roleNode is the `property_declaration`; a `statements`
            // ancestor marks it as local. Real stored/computed members (class/struct/enum/top-level) survive.
            if( isDef && kind == SymKind::Var && le.lang == Lang::Swift && isSwiftLocalBinding( roleNode ) )
            {
                continue;
            }

            // the gated capture classes — r3 q10 constants (plus the §7b CUDA memory-space policy for the
            // uninitialized C++ shape, which needs the captured declaration node), JS export/prototype
            // assignments — in one drop decision (see dropGatedCapture for the per-class rationale and why
            // none of this can live in the query as a #match?/#eq? predicate).
            if( isDef && dropGatedCapture( defCapSv, le.lang, nameTxt, nameNode, roleNode, src ) )
            {
                continue;
            }

            if( isDef )
            {
                RawDef d;
                d.fileId    = fileId;
                d.line      = nameRow + 1;   // the identifier's line — most accurate, dedup-stable
            // The C++ tags query captures @definition on the function_declarator (name+params) — its
            // span excludes the return type AND the body. Walk up to the nearest ancestor owning a
            // "body" field (the real function_definition) so [startByte,endByte) spans the WHOLE def:
            // return type + signature + body. Fixes --expand bodies, --pack-signatures return-types,
            // AND reference enclosing-attribution (a call in a body is now inside its function span).
            // Grammars whose @definition node already owns the body (class/struct/enum) don't climb.
            TSNode defNode = roleNode;
            // defBodyNodeOf = the `body:` field, PLUS the macro-edges round's one addition: a #define's
            // replacement text (`value:` field) is adopted as a macro symbol's body, set before the climb
            // below so the climb is skipped for macros.
            TSNode body    = defBodyNodeOf( roleNode, kind );
            // LB-E testmacroblock: the def is TWO SIBLING nodes (see testMacroBlockPartsOf) — adopt the
            // sibling compound_statement as the body and the title literal as the name BEFORE the shared
            // span/complexity code below. The span's endByte and the loc row window are extended past
            // defNode's own end further down (no single node covers both siblings).
            const bool isTestMacroBlock = ( defCapSv == "definition.testmacroblock" );
            if( isTestMacroBlock )
            {
                const TestMacroBlockParts parts = testMacroBlockPartsOf( roleNode, src );
                if( !parts.ok )
                {
                    continue;   // dropGatedCapture already vetoed non-candidates — guard, don't assert
                }
                body     = parts.body;
                nameNode = parts.title;
                nameTxt  = testMacroTitleOf( parts.title, src );
                nameByte = ts_node_start_byte( parts.title );
                nameRow  = ts_node_start_point( parts.title ).row;
                d.line   = nameRow + 1;   // re-seat: d.line above was filled from the @name capture (the macro identifier)
            }
            // A Var's span is its own declaration — never climb. The climb exists to find a FUNCTION's
            // body; for a var it can only steal a container's span (a Ruby class-level constant's parent
            // chain is body_statement → class, and class owns a "body" field, so the climb would hand the
            // constant THE WHOLE CLASS — the exact Rust-method span bug the H4 W3 note above describes).
            // No-op for every pre-existing Var capture (Swift/C#/Go/Python parents hit a scope-stop or the
            // file root before any "body"-owning ancestor — verified byte-identical on the gate corpora).
            // A Field's span is its own field_declaration / defining assignment — the Var rule, same reason.
            if( ts_node_is_null( body ) && kind != SymKind::Var && kind != SymKind::Field )
            {
                TSNode child = roleNode;
                TSNode p     = ts_node_parent( roleNode );
                for( int guard = 0; !ts_node_is_null( p ) && guard < 4; ++guard )
                {
                    const char* pt = ts_node_type( p );
                    // STOP at a type/namespace/file scope: a function's body never lives above one of
                    // these, so reaching here means roleNode is a prototype/declaration with no body.
                    // (Without this, an in-class method declaration would climb into class_specifier and
                    // wrongly grab the whole CLASS body as its span — corrupting spans + ref attribution.)
                    const bool scope =    std::strcmp( pt, "class_specifier" ) == 0        || std::strcmp( pt, "struct_specifier" ) == 0
                                       || std::strcmp( pt, "field_declaration_list" ) == 0 || std::strcmp( pt, "declaration_list" ) == 0
                                       || std::strcmp( pt, "namespace_definition" ) == 0   || std::strcmp( pt, "enum_specifier" ) == 0
                                       || std::strcmp( pt, "translation_unit" ) == 0       || std::strcmp( pt, "source_file" ) == 0       // Swift top
                                       || std::strcmp( pt, "class_body" ) == 0             || std::strcmp( pt, "protocol_body" ) == 0     // Swift type bodies
                                       || std::strcmp( pt, "enum_class_body" ) == 0
                                       || std::strcmp( pt, "class_interface" ) == 0        || std::strcmp( pt, "class_implementation" ) == 0   // ObjC
                                       || std::strcmp( pt, "implementation_definition" ) == 0 || std::strcmp( pt, "protocol_declaration" ) == 0
                                       || std::strcmp( pt, "compound_statement" ) == 0     || std::strcmp( pt, "block" ) == 0;   // a function BODY: a block-scope
                    // `Type v(args);` (most-vexing-parse) must not climb up and steal its enclosing function's span. A real
                    // function definition's declarator parents directly to function_definition (found at hop 1, above), so this never fires for it.
                    if( scope )
                    {
                        // prototype/declaration: use the member/decl wrapper as the span so the RETURN
                        // TYPE is included (not just the declarator), WITHOUT grabbing the class body.
                        const char* ct = ts_node_type( child );
                        if( std::strcmp( ct, "field_declaration" ) == 0 || std::strcmp( ct, "declaration" ) == 0 )
                        {
                            defNode = child;
                        }
                        break;
                    }
                    // Adopt an ancestor's span only if roleNode sits OUTSIDE its body — i.e. roleNode is the
                    // ancestor's own signature/declarator (the C++ function_declarator → function_definition
                    // hop this climb exists for). A def spelled INSIDE the body is a different, NESTED
                    // definition — a JS/TS named const-closure (`const f = (..) => {..}` in a function body) —
                    // and adopting here broadcast the encloser's whole span (loc/cx/params/nest) onto every
                    // such closure (webpack lib/html/syntax.js: eight closures inside the 3439-line `tokenize`
                    // all reported loc=3439 cx=487). The enclosing statement_block is not in the scope-stop
                    // list above (only C-family compound_statement/block are), so nested defs escaped upward;
                    // containment is the grammar-agnostic stop. Gate: test/jsnestedcheck.sh.
                    const TSNode pb = ts_node_child_by_field_name( p, "body", 4 );
                    if( !ts_node_is_null( pb ) )
                    {
                        if( !spanContains( pb, roleNode ) ) { defNode = p; body = pb; }
                        break;
                    }
                    child = p;
                    p     = ts_node_parent( p );
                }
            }

            // ObjC-only body-field fallback for the grammar that exposes a body as an unnamed CHILD, not a
            // named "body" field. C++ function_definition owns a "body" field (found above); the ObjC grammar
            // never does, so the field lookup returns null and bodyByte would stay 0 for a real definition —
            // making an @implementation def indistinguishable from its @interface DECL (both bodyByte==0). That
            // breaks BOTH the same-file decl/def collapse (3a-bis) and graph.h's cross-file hasBody
            // (endByte > sigEndByte), doubling every ObjC symbol node AND its call edges. Recover the
            // body-present signal from a direct child:
            //   - a METHOD def: a bare `compound_statement` / `function_body` / `block` child (the `{...}`).
            //   - an ObjC CLASS: an @implementation carries `implementation_definition` member children; the
            //     matching @interface carries only `method_declaration`s → so an `implementation_definition`
            //     child is exactly "this is the class's definition, not its forward @interface".
            // A bodyLESS declaration (@interface method / @interface class) has none of these children →
            // bodyByte stays 0 → it stays a decl (the discriminant the collapse needs). GATED to Lang::ObjC so
            // C++/Python/Rust/Go/TS/Swift bodyByte — and therefore their sigEndByte, spans, and node/edge
            // output — are BYTE-for-byte unchanged (a .mm's C++ functions take the C "body"-field path above
            // and never reach here). See test/langcheck.sh c.m and the byte-identical src/ regression gate.
            if( ts_node_is_null( body ) && le.lang == Lang::ObjC )
            {
                const std::uint32_t childCount = ts_node_child_count( defNode );
                for( std::uint32_t ci = 0; ci < childCount; ++ci )
                {
                    const TSNode ch = ts_node_child( defNode, ci );
                    const char*  ct = ts_node_type( ch );
                    if( std::strcmp( ct, "compound_statement" ) == 0     || std::strcmp( ct, "function_body" ) == 0
                        || std::strcmp( ct, "block" ) == 0               || std::strcmp( ct, "implementation_definition" ) == 0 )
                    { body = ch; break; }
                }
            }

            d.startByte = ts_node_start_byte( defNode );
            d.endByte   = isTestMacroBlock ? ts_node_end_byte( body ) : ts_node_end_byte( defNode );   // LB-E: the span runs THROUGH the sibling block
            d.nameByte  = nameByte;
            d.bodyByte  = ts_node_is_null( body ) ? 0u : ts_node_start_byte( body );
            const bool  fnOrMethod = ( kind == SymKind::Function || kind == SymKind::Method );
            // LB-E: for a testmacroblock the body SIBLING is where the code lives — complexityOf walks
            // INSIDE its root node, so handing it defNode (the bare macro statement) would count nothing.
            const auto [ cxVal, ccxVal, nestVal, localsVal, ppAltVal, humpsVal, deepVal, evVal, evWhyVal ] = fnOrMethod ? complexityOf( isTestMacroBlock ? body : defNode, src, le.lang ) : Complexity{ 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, {} };
            d.cx        = cxVal;
            d.ccx       = ccxVal;
            d.locals    = localsVal;   // Phase 1: floor count, C/C++ only (model.h localsCountedLang) — 0 elsewhere, never emitted there
            // ppalt disclosure (model.h Symbol::ppAlt). Saturating at 65535 on purpose: a def past that
            // bound is beyond every triage threshold, and the attribute's claim ("the body carries
            // alternatives") is already made at 1.
            d.ppAlt     = fnOrMethod ? std::uint16_t( ppAltVal > 65535u ? 65535u : ppAltVal ) : std::uint16_t( 0 );
            // Q4 size smells (SIZE = master variable): physical LOC = span line count (end row − start row + 1);
            // param count + max nesting for functions/methods only (0 otherwise, absent in emit). All descriptive.
            {
                const std::uint32_t startRow = ts_node_start_point( defNode ).row;
                const std::uint32_t endRow   = ts_node_end_point( isTestMacroBlock ? body : defNode ).row;   // LB-E: rows through the sibling block
                d.loc = ( endRow >= startRow ) ? ( endRow - startRow + 1u ) : 1u;
            }
            d.params    = fnOrMethod ? countParams( defNode ) : std::uint16_t( 0 );
            // LB-E: a testmacroblock's parameter surface is the MACRO's business, not visible here — claim
            // inexact so the resolver's arity narrowing never trusts params=0 on a test-title symbol.
            d.arityExact = ( fnOrMethod && !isTestMacroBlock ) ? std::uint8_t( cc_paramArityExact( defNode, le.lang, kind ) ? 1 : 0 ) : std::uint8_t( 0 );   // B2.2
            // L8: the in-file test-scope bit, for EVERY kind (a `#[cfg(test)] mod` and a `class TestFoo`
            // are themselves symbols, and dropping the members while keeping the shell would be a worse
            // answer than either). Runs on defNode, whose ancestors are the enclosing scopes.
            d.testScope = isTestMacroBlock ? std::uint8_t( 1 ) : std::uint8_t( inFileTestScope( defNode, src, le.lang ) );   // LB-E: a test macro IS the in-file convention
            d.maxNest   = fnOrMethod ? std::uint8_t( nestVal > 255u ? 255u : nestVal ) : std::uint8_t( 0 );
            // The nesting profile (model.h Symbol::humps/deepLoc). Saturating at 65535 on purpose: a def past
            // either bound is beyond every triage threshold, and deepLoc is a floor already, so a clamp there
            // stays honest in the direction the attribute already claims.
            d.humps     = fnOrMethod ? std::uint16_t( humpsVal > 65535u ? 65535u : humpsVal ) : std::uint16_t( 0 );
            d.deepLoc   = fnOrMethod ? std::uint16_t( deepVal  > 65535u ? 65535u : deepVal  ) : std::uint16_t( 0 );
            // essential complexity (model.h Symbol::ev): already saturated inside ev_finalize; 0 for
            // non-function kinds and outside evCountedLang, matching the emitters' omission rule.
            d.ev        = fnOrMethod ? std::uint16_t( evVal > 65535u ? 65535u : evVal ) : std::uint16_t( 0 );
            d.evWhy     = fnOrMethod ? evWhyVal : std::array<std::uint8_t, kEvWhyTagCount>{};
            d.kind      = kind;
            d.lang      = le.lang;
            d.name      = isTestMacroBlock ? std::string( nameTxt ) : defNameFromCapture( le.lang, nameTxt );   // LB-E: a title is a display string — see testMacroTitleOf
            if( le.lang == Lang::Cpp )                              // canonical scope (E#4): out-of-line `A::b` → "A", else enclosing class/namespace
            {
                d.scope = qualifierOf( nameNode, src );
                if( d.scope.empty() )
                {
                    d.scope = enclosingScopeOf( nameNode, src );
                }
            }
            else if( le.lang == Lang::Python )
            { // P2-D Rule 1: enclosing class of a Python method → `self.m()` narrows to Class::m
                d.scope = enclosingScopeOf( nameNode, src );
            }
            else if( le.lang == Lang::Rust )
            { // H4: `impl Widget { fn new() }` → "Widget" — see rustEnclosingScopeOf
                d.scope = rustEnclosingScopeOf( nameNode, src, /*includeModules=*/true );
            }
            defs.push_back( std::move( d ) );
            if( kind == SymKind::Class || kind == SymKind::Struct || kind == SymKind::Interface )
            {
                captureBases( defNode, fileId, le.lang, src, refs );    // IS-A: inheritance edges (derived → base)
                captureFields( defNode, fileId, le.lang, src, refs );   // HAS-A: member-variable type edges (S5-E)
            }
            else if( kind == SymKind::Macro )
            {
                captureMacroBodyCalls( roleNode, fileId, le.lang, src, refs );   // macro-edges: the graph connects THROUGH the macro
            }
            }
            else if( isRef )
            {
                // H4: a C++ cast keyword is not a call — see isCppCastKeyword. Valid input, skipped, no alert.
                if( le.lang == Lang::Cpp && isCppCastKeyword( nameTxt ) )
                {
                    continue;
                }

                // using-declaration re-exports (r9 loss bucket 1): @reference.import marks the C++
                // `using ns::name;` tags pattern. The site becomes a role="import" use-site of the target
                // (never a call edge — graph.h admits Call+Macro only), and the grammar KEYWORD forms
                // (`using namespace ns;` / `using enum E;`) are dropped here at capture time, where the
                // query predicate a tags pattern cannot express IS enforceable (see the helper's note).
                const bool isImportRef = ( refCapSv == "reference.import" );
                if( isImportRef && usingDeclarationIsDirective( roleNode ) )
                {
                    continue;
                }

                RawRef r;
                r.fileId    = fileId;
                r.startByte = ts_node_start_byte( roleNode );
                r.line      = ts_node_start_point( roleNode ).row + 1;   // ABS-3: 1-based use-site line for --uses
                r.lang      = le.lang;
                r.role      = isImportRef ? RefRole::Import : RefRole::Call;   // ABS-3: @reference.call is a call use-site; @reference.import a using-decl re-export
                r.name      = finalSegment( nameTxt );
                if( le.lang == Lang::Cpp )
                {
                    r.qualifier = qualifierOf( nameNode, src ); // `A::b()` → "A" (E#4 canonical resolve)
                }
                else if( le.lang == Lang::Rust )
                {
                    r.qualifier = rustQualifierOf( nameNode, src ); // H4: `Widget::new()` → "Widget"
                }

                // H4 RE-SPLIT: the widened qualified-call pattern binds the INNER node, so a 3+-segment call's
                // captured text still carries scope (`inner::targetFn`). Recover the pair the canonical tier
                // keys on — name = the final segment, qualifier = the IMMEDIATE scope — from the text itself.
                // This must run INSTEAD OF the finalSegment() above (it overwrites both fields): finalSegment
                // truncates at the first '<', which would name `numeric_limits<std::size_t>::max` as
                // `numeric_limits` and mint an edge to the wrong symbol. Inert for every 2-segment call
                // (`rw::midFn` binds a bare identifier — no top-level `::` in the text) and for
                // `ns::tmplFn<int>()` (whose `::` sits inside no group but whose captured text is just
                // `tmplFn<int>`), so those keep their qualifierOf() result untouched.
                if( le.lang == Lang::Cpp )
                {
                    // An OPERATOR tail is recognised first: its `<`/`>` are part of the NAME, so handing it to
                    // the angle-depth scan below binds the wrong scope for the whole `>` family. See
                    // operatorNameStart. When the operator spelling starts at index 0 the capture IS the bare
                    // operator name, its parent is the qualified_identifier, and qualifierOf() already put the
                    // immediate scope in r.qualifier — nothing to re-split.
                    const std::size_t opStart = operatorNameStart( nameTxt );
                    const bool        opScoped = opStart != std::string_view::npos && opStart >= 2
                                              && nameTxt[ opStart - 1 ] == ':' && nameTxt[ opStart - 2 ] == ':';
                    if( opScoped )
                    {
                        r.name      = finalSegment( nameTxt.substr( opStart ) );                                  // `operator>` verbatim
                        r.qualifier = immediateScope( namesplit::stripTemplateArgs( nameTxt.substr( 0, opStart - 2 ) ) );
                    }
                    else if( opStart == std::string_view::npos )
                    {
                        if( const std::size_t sep = lastTopLevelScopeSep( nameTxt ); sep != std::string_view::npos )
                        {
                            r.name      = finalSegment( nameTxt.substr( sep + 2 ) );
                            r.qualifier = immediateScope( namesplit::stripTemplateArgs( nameTxt.substr( 0, sep ) ) );
                        }
                    }
                }

                if( !isImportRef )                                                       // an import site has no receiver and no argument list —
                {                                                                        //   the defaults (RecvKind::None, argCountKnown=false) are the truth
                    RecvShape rs = receiverOf( nameNode, le.lang, src );                 // P2-D: `this`/`self`/`x`/`base.field` shape
                    r.recv = rs.kind;  r.recvVar = std::move( rs.var );                  //   → one-hop narrowing in resolve.h
                    r.fieldName = std::move( rs.field );                                 //   depth-2 intermediate field; "" otherwise
                    auto [ ac, ak ] = callArity( nameNode, le.lang, src );               // B2.2: call-site positional arg count
                    r.argCount = ac;  r.argCountKnown = ak;                              //   → arity filter in graph.h
                }
                refs.push_back( std::move( r ) );
            }
        }
    }

    foldFieldDefs( defs, firstDefOfFile, le.lang );   // member-variable round: owner-less fields drop, Python fields fold to one per (class, name)
}

}   // namespace — ingest_sidecap.h section of ingest.cpp

}   // namespace rw
