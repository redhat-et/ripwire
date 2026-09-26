#!/usr/bin/env python3
# tsparse.py — the INDEPENDENT function-grain parser (§4.3, decision A9 option 2): Python ctypes over the
# tree-sitter runtime and grammars vendored in this tree (third_party/deps), compiled locally into one shared
# library in a cache directory. It uses NONE of ripwire's extraction code or queries: the definition queries and
# the node-type table below are this harness's own, frozen here and pinned by tests.
#
# Limitation, stated in the registration: labels and ripwire share the same upstream grammar builds (and the
# runtime's one vendored patch, a query-compile leak fix in query.c that does not touch parsing), so a grammar
# mis-parse is common-mode between the label parser and the binary under test.
#
# Pinned sources (commit — tag), from CMakeLists.txt's FetchContent pins of the vendored copies:
#   runtime    7f534862c3ec939c3a6ee147f7600ef5c1bf900f  v0.26.9
#   c          7fa1be1b694b6e763686793d97da01f36a0e5c12  v0.24.1
#   cpp        f41e1a044c8a84ea9fa8577fdd2eab92ec96de02  v0.23.4
#   python     bffb65a8cfe4e46290331dfef0dbf0ef3679de11  v0.23.6
#   go         3c3775faa968158a8b4ac190a7fda867fd5fb748  v0.23.4
#   java       94703d5a6bed02b98e438d7cad1136c01a60ba2c  v0.23.5
#   rust       cad8a206f2e4194676b9699f26f6560d07130d3f  v0.23.2
#   typescript f975a621f4e7f532fe322e13c4f79495e0a7b2e7  v0.23.2 (typescript/ and tsx/)
#
# A UNIT is a named function or method WITH A BODY (§1). A named function nested inside another collapses into
# the outermost one (lambdas, closures, local classes' methods included), so units never overlap. Its scope is
# the innermost enclosing named type/namespace/module/impl (or the qualifier of a C++ out-of-class definition,
# or a Go method's receiver type). Rust items under a `#[cfg(test)]` module, and `#[test]` functions, are not
# product source and are dropped.
import ctypes, hashlib, os, re, subprocess, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
ROOT = os.path.dirname( os.path.dirname( HERE ) )
DEPS = os.path.join( ROOT, "third_party", "deps" )
sys.path.insert( 0, HERE )

MAX_FILE_BYTES = 4 * 1024 * 1024       # larger blobs are counted unread, never parsed

# grammar -> (source dir relative to DEPS, exported language symbol)
GRAMMARS = {
    "c": ( "c/src", "tree_sitter_c" ),
    "cpp": ( "cpp/src", "tree_sitter_cpp" ),
    "python": ( "python/src", "tree_sitter_python" ),
    "go": ( "go/src", "tree_sitter_go" ),
    "java": ( "java/src", "tree_sitter_java" ),
    "rust": ( "rust/src", "tree_sitter_rust" ),
    "typescript": ( "ts_typescript/typescript/src", "tree_sitter_typescript" ),
    "tsx": ( "ts_typescript/tsx/src", "tree_sitter_tsx" ),
}


def grammar_for( path ):
    low = path.lower()
    if low.endswith( ".c" ):
        return "c"
    if low.endswith( ( ".h", ".cc", ".cpp", ".cxx", ".c++", ".hpp", ".hh", ".hxx", ".h++", ".ipp", ".inl", ".tcc" ) ):
        return "cpp"
    if low.endswith( ".py" ):
        return "python"
    if low.endswith( ".go" ):
        return "go"
    if low.endswith( ".java" ):
        return "java"
    if low.endswith( ".rs" ):
        return "rust"
    if low.endswith( ".tsx" ):
        return "tsx"
    if low.endswith( ( ".ts", ".mts", ".cts" ) ):
        return "typescript"
    return None


# ── queries: @def = the definition node (its span is the unit), @name = its name, @scope/@sname = an enclosing
#    named scope; @decl/@fname = C/C++ declarator parts; @recv = a Go receiver; @attr/@item = Rust attributes ──
_C_FAMILY = """
(function_definition declarator: (_) @decl body: (compound_statement)) @def
(function_declarator declarator: (_) @fname)
"""
QUERIES = {
    "c": _C_FAMILY + """
(struct_specifier name: (_) @sname body: (_)) @scope
""",
    "cpp": _C_FAMILY + """
(class_specifier name: (_) @sname body: (_)) @scope
(struct_specifier name: (_) @sname body: (_)) @scope
(union_specifier name: (_) @sname body: (_)) @scope
(namespace_definition name: (_) @sname body: (_)) @scope
""",
    "python": """
(function_definition name: (identifier) @name body: (block)) @def
(class_definition name: (identifier) @sname body: (block)) @scope
""",
    "go": """
(function_declaration name: (identifier) @name body: (block)) @def
(method_declaration receiver: (parameter_list) @recv name: (field_identifier) @name body: (block)) @def
""",
    "java": """
(method_declaration name: (identifier) @name body: (block)) @def
(constructor_declaration name: (identifier) @name body: (constructor_body)) @def
(compact_constructor_declaration name: (identifier) @name body: (block)) @def
(class_declaration name: (identifier) @sname body: (_)) @scope
(interface_declaration name: (identifier) @sname body: (_)) @scope
(enum_declaration name: (identifier) @sname body: (_)) @scope
(record_declaration name: (identifier) @sname body: (_)) @scope
(annotation_type_declaration name: (identifier) @sname body: (_)) @scope
""",
    "rust": """
(function_item name: (identifier) @name body: (block)) @def
(impl_item type: (_) @sname body: (declaration_list)) @scope
(trait_item name: (type_identifier) @sname body: (declaration_list)) @scope
(mod_item name: (identifier) @sname body: (declaration_list)) @scope
((attribute_item) @attr . [(mod_item) (function_item)] @item)
""",
}
_TS = """
(function_declaration name: (identifier) @name body: (statement_block)) @def
(generator_function_declaration name: (identifier) @name body: (statement_block)) @def
(method_definition name: (_) @name body: (statement_block)) @def
(variable_declarator name: (identifier) @name value: [(arrow_function) (function_expression)]) @def
(public_field_definition name: (_) @name value: [(arrow_function) (function_expression)]) @def
(class_declaration name: (type_identifier) @sname body: (class_body)) @scope
(abstract_class_declaration name: (type_identifier) @sname body: (class_body)) @scope
(internal_module name: (_) @sname body: (statement_block)) @scope
"""
QUERIES[ "typescript" ] = _TS
QUERIES[ "tsx" ] = _TS

# the frozen node-type table the C/C++ declarator walk accepts as a function's name
C_NAME_TYPES = ( "identifier", "field_identifier", "qualified_identifier", "destructor_name", "operator_name",
                 "template_function", "operator_cast", "template_method" )


# ── building and loading the library ────────────────────────────────────────────────────────────────────
def _sources():
    rt = os.path.join( DEPS, "tree_sitter", "lib" )
    units = [ ( os.path.join( rt, "src", "lib.c" ), [ os.path.join( rt, "include" ), os.path.join( rt, "src" ) ] ) ]
    for g, ( rel, _ ) in sorted( GRAMMARS.items() ):
        d = os.path.join( DEPS, rel )
        for f in ( "parser.c", "scanner.c" ):
            if os.path.exists( os.path.join( d, f ) ):
                units.append( ( os.path.join( d, f ), [ d, os.path.join( rt, "include" ) ] ) )
    return units


def source_digest():
    h = hashlib.sha256()
    for f, _ in _sources():
        with open( f, "rb" ) as fh:
            h.update( os.path.relpath( f, DEPS ).encode() + b"\0" + hashlib.file_digest( fh, "sha256" ).digest() )
    return h.hexdigest()


def build( cache_dir, cc="cc", jobs=4 ):
    """Compile the runtime and grammars into cache_dir/libm1ts-<digest>.so (once). Returns its path."""
    digest = source_digest()[ :16 ]
    out = os.path.join( cache_dir, "libm1ts-%s.so" % digest )
    if os.path.exists( out ):
        return out
    os.makedirs( os.path.join( cache_dir, "obj" ), exist_ok=True )
    objs, procs = [], []
    for i, ( src, incs ) in enumerate( _sources() ):
        obj = os.path.join( cache_dir, "obj", "%02d_%s.o" % ( i, re.sub( r"[^A-Za-z0-9]+", "_", os.path.relpath( src, DEPS ) ) ) )
        objs.append( obj )
        if os.path.exists( obj ):
            continue
        cmd = [ "nice", "-n", "10", cc, "-O2", "-fPIC", "-std=c11", "-w", "-c", src, "-o", obj ] + [ a for d in incs for a in ( "-I", d ) ]
        procs.append( subprocess.Popen( cmd ) )
        if len( procs ) >= jobs:
            if procs.pop( 0 ).wait() != 0:
                raise RuntimeError( "compile failed" )
    for p in procs:
        if p.wait() != 0:
            raise RuntimeError( "compile failed" )
    subprocess.run( [ cc, "-shared", "-o", out + ".tmp" ] + objs, check=True )
    os.replace( out + ".tmp", out )
    return out


class TSPoint( ctypes.Structure ):
    _fields_ = [ ( "row", ctypes.c_uint32 ), ( "column", ctypes.c_uint32 ) ]


class TSNode( ctypes.Structure ):
    _fields_ = [ ( "context", ctypes.c_uint32 * 4 ), ( "id", ctypes.c_void_p ), ( "tree", ctypes.c_void_p ) ]


class TSQueryCapture( ctypes.Structure ):
    _fields_ = [ ( "node", TSNode ), ( "index", ctypes.c_uint32 ) ]


class TSQueryMatch( ctypes.Structure ):
    _fields_ = [ ( "id", ctypes.c_uint32 ), ( "pattern_index", ctypes.c_uint16 ), ( "capture_count", ctypes.c_uint16 ),
                 ( "captures", ctypes.POINTER( TSQueryCapture ) ) ]


def _bind( lib ):
    P, U32, B = ctypes.c_void_p, ctypes.c_uint32, ctypes.c_bool
    sig = {
        "ts_parser_new": ( P, [] ), "ts_parser_delete": ( None, [ P ] ), "ts_parser_set_language": ( B, [ P, P ] ),
        "ts_parser_parse_string": ( P, [ P, P, ctypes.c_char_p, U32 ] ), "ts_tree_delete": ( None, [ P ] ),
        "ts_tree_root_node": ( TSNode, [ P ] ), "ts_node_has_error": ( B, [ TSNode ] ),
        "ts_node_start_byte": ( U32, [ TSNode ] ), "ts_node_end_byte": ( U32, [ TSNode ] ),
        "ts_node_start_point": ( TSPoint, [ TSNode ] ), "ts_node_end_point": ( TSPoint, [ TSNode ] ),
        "ts_node_type": ( ctypes.c_char_p, [ TSNode ] ),
        "ts_query_new": ( P, [ P, ctypes.c_char_p, U32, ctypes.POINTER( U32 ), ctypes.POINTER( U32 ) ] ),
        "ts_query_capture_count": ( U32, [ P ] ),
        "ts_query_capture_name_for_id": ( ctypes.c_char_p, [ P, U32, ctypes.POINTER( U32 ) ] ),
        "ts_query_cursor_new": ( P, [] ), "ts_query_cursor_exec": ( None, [ P, P, TSNode ] ),
        "ts_query_cursor_next_match": ( B, [ P, ctypes.POINTER( TSQueryMatch ) ] ),
        "ts_language_abi_version": ( U32, [ P ] ),
    }
    for name, ( res, args ) in sig.items():
        f = getattr( lib, name )
        f.restype, f.argtypes = res, args
    for _, sym in GRAMMARS.values():
        getattr( lib, sym ).restype = P


class Parser:
    """units(path, data) -> [(scope, name, start_line, end_line)], and per-file parse bookkeeping."""
    grain = "function"

    def __init__( self, lib_path ):
        self.lib = ctypes.CDLL( lib_path )
        _bind( self.lib )
        self.parser = self.lib.ts_parser_new()
        self.langs, self.queries, self.cursor = {}, {}, self.lib.ts_query_cursor_new()
        self.stats = dict( files=0, parsed=0, with_error=0, too_big=0, failed=0 )

    def _lang( self, g ):
        if g not in self.langs:
            lang = getattr( self.lib, GRAMMARS[ g ][ 1 ] )()
            src = QUERIES[ g ].encode()
            off, typ = ctypes.c_uint32(), ctypes.c_uint32()
            q = self.lib.ts_query_new( lang, src, len( src ), ctypes.byref( off ), ctypes.byref( typ ) )
            if not q:
                raise RuntimeError( "query for %s failed at offset %d (type %d)" % ( g, off.value, typ.value ) )
            names = []
            for i in range( self.lib.ts_query_capture_count( q ) ):
                n = ctypes.c_uint32()
                names.append( self.lib.ts_query_capture_name_for_id( q, i, ctypes.byref( n ) )[ :n.value ].decode() )
            self.langs[ g ] = lang
            self.queries[ g ] = ( q, names )
        return self.langs[ g ], self.queries[ g ]

    def parse_file( self, path, data ):
        """Returns (units, status) with status in parsed / with_error / too_big / failed / unsupported."""
        g = grammar_for( path )
        if g is None:
            return [], "unsupported"
        self.stats[ "files" ] += 1
        if len( data ) > MAX_FILE_BYTES:
            self.stats[ "too_big" ] += 1
            return [], "too_big"
        lang, ( q, names ) = self._lang( g )
        L = self.lib
        if not L.ts_parser_set_language( self.parser, lang ):
            raise RuntimeError( "ABI mismatch for %s" % g )
        tree = L.ts_parser_parse_string( self.parser, None, data, len( data ) )
        if not tree:
            self.stats[ "failed" ] += 1
            return [], "failed"
        try:
            root = L.ts_tree_root_node( tree )
            status = "with_error" if L.ts_node_has_error( root ) else "parsed"
            self.stats[ status ] += 1
            L.ts_query_cursor_exec( self.cursor, q, root )
            m = TSQueryMatch()
            matches = []
            while L.ts_query_cursor_next_match( self.cursor, ctypes.byref( m ) ):
                caps = {}
                for i in range( m.capture_count ):
                    c = m.captures[ i ]
                    n = c.node
                    sp, ep = L.ts_node_start_point( n ), L.ts_node_end_point( n )
                    caps[ names[ c.index ] ] = ( L.ts_node_start_byte( n ), L.ts_node_end_byte( n ), sp.row, ep.row, ep.column,
                                                 L.ts_node_type( n ).decode() )
                matches.append( caps )
        finally:
            L.ts_tree_delete( tree )
        return assemble( g, matches, data ), status

    def units( self, path, data ):
        return self.parse_file( path, data )[ 0 ]


# ── turning raw matches into units (pure Python; unit-tested without the library) ───────────────────────
def _text( data, cap ):
    return data[ cap[ 0 ]:cap[ 1 ] ].decode( "utf-8", "replace" )


def _end_line( cap ):
    """1-based inclusive last line of a node (an end at column 0 belongs to the previous line)."""
    return cap[ 3 ] + 1 if cap[ 4 ] > 0 or cap[ 3 ] == cap[ 2 ] else cap[ 3 ]


def _strip_generics( s ):
    prev = None
    while prev != s:
        prev, s = s, re.sub( r"<[^<>]*>", "", s )
    return s


def _c_name( data, decl, fnames ):
    """The C/C++ function name inside a definition's declarator: the OUTERMOST function_declarator's declarator
    within it (a function-pointer parameter is a nested, later one). Returns (scope_or_None, name) or None."""
    inside = [ f for f in fnames if f[ 0 ] >= decl[ 0 ] and f[ 1 ] <= decl[ 1 ] and f[ 5 ] in C_NAME_TYPES ]
    if not inside:
        return None
    f = min( inside, key=lambda c: ( c[ 0 ], -c[ 1 ] ) )
    text = re.sub( r"\s+", "", _strip_generics( _text( data, f ) ) )
    if "::" in text:
        parts = [ p for p in text.split( "::" ) if p ]
        return ( parts[ -2 ] if len( parts ) > 1 else None ), parts[ -1 ]
    return None, text


def _go_receiver( data, recv ):
    t = _text( data, recv ).strip( "()" ).split( "," )[ 0 ].strip()
    t = _strip_generics( re.sub( r"\[.*\]", "", t ) )
    toks = t.replace( "*", " " ).split()
    return toks[ -1 ] if toks else ""


def assemble( g, matches, data ):
    defs, scopes, fnames, test_items = [], [], [], []
    for caps in matches:
        if "def" in caps:
            d = caps[ "def" ]
            if g in ( "c", "cpp" ):
                defs.append( [ d, None, caps[ "decl" ] ] )
            else:
                name = _text( data, caps[ "name" ] )
                scope = _go_receiver( data, caps[ "recv" ] ) if "recv" in caps else None
                defs.append( [ d, ( scope, name ), None ] )
        elif "scope" in caps:
            s = caps[ "scope" ]
            nm = re.sub( r"\s+", "", _strip_generics( _text( data, caps[ "sname" ] ) ) )
            if g == "rust" and caps[ "scope" ][ 5 ] == "impl_item":
                nm = nm.split( "::" )[ -1 ].lstrip( "&" )
            scopes.append( ( s[ 0 ], s[ 1 ], nm.split( "." )[ -1 ] ) )
        elif "fname" in caps:
            fnames.append( caps[ "fname" ] )
        elif "attr" in caps:
            a = re.sub( r"\s+", "", _text( data, caps[ "attr" ] ) )
            item = caps[ "item" ]
            if ( item[ 5 ] == "mod_item" and a.startswith( "#[cfg(" ) and re.search( r"\btest\b", a ) ) or \
               ( item[ 5 ] == "function_item" and re.match( r"#\[(tokio::|async_std::)?test\b", a ) ):
                test_items.append( ( item[ 0 ], item[ 1 ] ) )
    named = []
    for d, nm, decl in defs:
        if nm is None:
            nm = _c_name( data, decl, fnames )
            if nm is None:
                continue
        named.append( ( d, nm ) )
    # collapse nesting: keep only definitions not strictly inside another definition
    named.sort( key=lambda x: ( x[ 0 ][ 0 ], -x[ 0 ][ 1 ] ) )
    out, last_end = [], -1
    for d, ( qual, name ) in named:
        if d[ 0 ] < last_end:
            continue
        last_end = d[ 1 ]
        if any( a <= d[ 0 ] and d[ 1 ] <= b for a, b in test_items ):
            continue
        scope = qual
        if scope is None:
            inner = [ s for s in scopes if s[ 0 ] <= d[ 0 ] and d[ 1 ] <= s[ 1 ] ]
            scope = min( inner, key=lambda s: s[ 1 ] - s[ 0 ] )[ 2 ] if inner else ""
        out.append( ( scope, name, d[ 2 ] + 1, _end_line( d ) ) )
    return out
