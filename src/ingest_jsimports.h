#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_jsimports.h belongs only to ingest.cpp"
#endif

namespace rw
{
namespace
{

// ES imports carry three independent facts: local spelling, export spelling, and module.
//
// EXPORTS come in two shapes and BOTH are recorded, because the table is consulted as a REFUSAL: a name
// the table cannot find is a call the resolver declines to hand to the global name ladder. Seeing only
// the declaration form (`export function f(){}`) therefore does not merely miss `export { f }` — it
// DELETES the edge the ladder used to resolve correctly, which is a regression, not a gap. So:
//   * declaration form   `export function f(){}` / `export const f = () => {}` — the span is the
//                        declaration itself, and only a symbol INSIDE it may be the export.
//   * clause form        `export { f }` / `export { f as g }` — the exported name is the alias, the
//                        binding it names is module-scoped and declared ANYWHERE in the file, so the
//                        span is the whole program. `var` is the EXPORTED name (what an importer
//                        writes) and `importedName` the LOCAL one (what the definition is called).
// Re-export/barrel clauses (`export { f } from './m.js'`) are deliberately NOT recorded: the definition
// lives in a third file this table does not chase, so recording the name would let a refusal fire on
// evidence we do not have. Left out, the name is simply UNLISTED, and buildJsImportTables degrades an
// unlisted import to the name ladder — the pre-import behaviour, which resolved barrels correctly.
// Default imports request the export spelling "default"; their local name is never a global fallback.
// Named default declarations and local identifier exports use the same table. Anonymous expressions
// have no symbol identity here and remain unresolved rather than borrowing a same-spelled function.
// Type-only imports remain a known gap (recorded with an empty importedName, and refused, never sprayed).
// #62: forwards to preprocdead.h's shared spelling (which adopted this function's null guard for the
// purpose) rather than holding a third copy of the same strcmp - slice.h's sliceKindIs was the second.
inline bool jsNodeIs( TSNode node, const char* kind )
{
    return rw::preprocNodeKindIs( node, kind );
}

inline bool jsHasToken( TSNode node, const char* token )
{
    ChildCursor cursor( node );
    std::vector<TSNode> children;
    collectChildren( node, cursor.cur, children );
    for( TSNode child : children )
    {
        if( jsNodeIs( child, token ) ) { return true; }
    }
    return false;
}

inline bool jsFunctionScope( TSNode node )
{
    const char* kind = ts_node_type( node );
    return std::strcmp( kind, "function_declaration" ) == 0 || std::strcmp( kind, "function_expression" ) == 0
        || std::strcmp( kind, "generator_function_declaration" ) == 0 || std::strcmp( kind, "generator_function" ) == 0
        || std::strcmp( kind, "arrow_function" ) == 0 || std::strcmp( kind, "method_definition" ) == 0;
}

// Walk binding PATTERNS, never initializer expressions or type annotations. Destructuring keys do not bind.
inline std::vector<std::string> jsPatternNames( TSNode pattern, std::string_view src )
{
    std::vector<std::string> names;
    std::vector<TSNode> pending;
    if( !ts_node_is_null( pattern ) ) { pending.push_back( pattern ); }
    while( !pending.empty() )
    {
        TSNode node = pending.back();
        pending.pop_back();
        const char* kind = ts_node_type( node );
        if( jsNodeIs( node, "identifier" ) || jsNodeIs( node, "shorthand_property_identifier_pattern" ) )
        {
            names.emplace_back( pattern::nodeText( node, src ) );
        }
        else if( jsNodeIs( node, "pair_pattern" ) || jsNodeIs( node, "assignment_pattern" )
                 || jsNodeIs( node, "object_assignment_pattern" ) || jsNodeIs( node, "required_parameter" ) || jsNodeIs( node, "optional_parameter" ) )
        {
            const NodeField field = jsNodeIs( node, "pair_pattern" ) ? NodeField::Value
                                  : ( jsNodeIs( node, "required_parameter" ) || jsNodeIs( node, "optional_parameter" ) ) ? NodeField::Pattern : NodeField::Left;
            TSNode child = fieldChild( node, field );
            if( ts_node_is_null( child ) ) { child = fieldChild( node, NodeField::Name ); }
            if( !ts_node_is_null( child ) ) { pending.push_back( child ); }
        }
        else if( std::strcmp( kind, "formal_parameters" ) == 0 || std::strcmp( kind, "array_pattern" ) == 0
                 || std::strcmp( kind, "object_pattern" ) == 0 || std::strcmp( kind, "rest_pattern" ) == 0 )
        {
            ChildCursor cursor( node );
            std::vector<TSNode> children;
            collectChildren( node, cursor.cur, children );
            for( TSNode child : children ) { pending.push_back( child ); }
        }
    }
    std::sort( names.begin(), names.end() );
    names.erase( std::unique( names.begin(), names.end() ), names.end() );
    return names;
}

// The (EXPORTED name, LOCAL name) pairs a `export { f }` / `export { f as g }` clause binds — the clause
// form of an export, whose target may be declared anywhere in the file. Empty, deliberately, for the two
// shapes this table must NOT claim to know: a RE-EXPORT (`export { f } from './m.js'`, whose definition is
// in a third file), and `export type { F }` (which binds no value and must never mint a call edge). An
// empty result leaves the name UNLISTED, which buildJsImportTables degrades to the name ladder.
inline std::vector<std::pair<std::string, std::string>> jsExportClauseNames( TSNode stmt, std::string_view src )
{
    std::vector<std::pair<std::string, std::string>> names;
    if( !ts_node_is_null( fieldChild( stmt, NodeField::Source ) ) || jsHasToken( stmt, "type" ) )
    {
        return names;
    }
    std::vector<TSNode> pending{ stmt };
    while( !pending.empty() )
    {
        TSNode node = pending.back();
        pending.pop_back();
        if( jsNodeIs( node, "export_specifier" ) )
        {
            TSNode local = fieldChild( node, NodeField::Name );
            TSNode alias = fieldChild( node, NodeField::Alias );
            if( ts_node_is_null( alias ) ) { alias = local; }
            if( jsNodeIs( local, "identifier" ) && jsNodeIs( alias, "identifier" ) && !jsHasToken( node, "type" ) )
            {
                names.emplace_back( std::string( pattern::nodeText( alias, src ) ), std::string( pattern::nodeText( local, src ) ) );
            }
        }
        else if( jsNodeIs( node, "export_statement" ) || jsNodeIs( node, "export_clause" ) )
        {
            ChildCursor cursor( node );
            std::vector<TSNode> nested;
            collectChildren( node, cursor.cur, nested );
            for( TSNode child : nested ) { pending.push_back( child ); }
        }
    }
    return names;
}

// Only a unique module value binding can supply an identifier default. Non-function declarations
// matter too: they do not all become symbols, but still make a same-named function ambiguous.
inline std::uint32_t jsModuleBindingCount( TSNode root, std::string_view name, std::string_view src )
{
    std::uint32_t count = 0;
    ChildCursor cursor( root );
    std::vector<TSNode> children;
    collectChildren( root, cursor.cur, children );
    for( TSNode stmt : children )
    {
        TSNode decl = jsNodeIs( stmt, "export_statement" ) ? fieldChild( stmt, NodeField::Declaration ) : stmt;
        if( ts_node_is_null( decl ) || jsHasToken( stmt, "type" ) ) { continue; }
        std::vector<TSNode> pending{ decl };
        while( !pending.empty() )
        {
            TSNode node = pending.back();
            pending.pop_back();
            TSNode binding{};
            if( jsNodeIs( node, "variable_declarator" ) || jsNodeIs( node, "function_declaration" )
                || jsNodeIs( node, "generator_function_declaration" ) || jsNodeIs( node, "class_declaration" )
                || jsNodeIs( node, "abstract_class_declaration" ) || jsNodeIs( node, "enum_declaration" ) )
            {
                binding = fieldChild( node, NodeField::Name );
            }
            else if( jsNodeIs( node, "import_specifier" ) && !jsHasToken( node, "type" ) )
            {
                binding = fieldChild( node, NodeField::Alias );
                if( ts_node_is_null( binding ) ) { binding = fieldChild( node, NodeField::Name ); }
            }
            else if( jsNodeIs( node, "identifier" ) ) { binding = node; }
            else if( jsNodeIs( node, "lexical_declaration" ) || jsNodeIs( node, "variable_declaration" )
                     || jsNodeIs( node, "import_statement" ) || jsNodeIs( node, "import_clause" )
                     || jsNodeIs( node, "named_imports" ) || jsNodeIs( node, "namespace_import" ) )
            {
                ChildCursor childCursor( node );
                std::vector<TSNode> nested;
                collectChildren( node, childCursor.cur, nested );
                for( TSNode child : nested ) { pending.push_back( child ); }
            }
            if( !ts_node_is_null( binding ) )
            {
                if( jsNodeIs( binding, "type_identifier" ) )
                {
                    if( pattern::nodeText( binding, src ) == name ) { ++count; }
                }
                else
                {
                    for( const std::string& local : jsPatternNames( binding, src ) )
                    {
                        if( local == name ) { ++count; }
                    }
                }
            }
        }
    }
    return count;
}

// FE-A: one top-level `const|let|var` statement's MODULE ALIASES (model.h LocalBindKind::ModuleAlias), handed to `emit` as
// ( declarator, local name, source, member, sourceIsIdentifier ):
//   `const x = require( 'm' )`          → ( x, m, "*", false )
//   `const { a, b: c } = require( 'm' )` → ( a, m, a, false ), ( c, m, b, false )
//   `const { a } = G`                   → ( a, G, a, true )   — G any identifier; graph.h decides whether it is a global
// The require shape is ingest_relations.h jsModuleLoadTarget's (bare `require`, one string argument) minus dynamic import().
// Any other declarator (a computed key, a rest element, a default value, a member RHS) records nothing: an absent alias
// leaves the call to the unchanged ladder. Each recorded declarator's start byte lands in `aliasDecls`, so the shadow
// walk below does not read the alias as a declaration hiding itself.
template <class Emit>
inline void captureJsModuleAliases( TSNode stmt, std::string_view src, HashMap<std::uint32_t, char>& aliasDecls, Emit&& emit )
{
    ChildCursor cursor( stmt );
    std::vector<TSNode> declarators;
    collectChildren( stmt, cursor.cur, declarators );
    for( TSNode declarator : declarators )
    {
        if( !jsNodeIs( declarator, "variable_declarator" ) ) { continue; }
        const TSNode name  = fieldChild( declarator, NodeField::Name );
        const TSNode value = fieldChild( declarator, NodeField::Value );
        if( ts_node_is_null( name ) || ts_node_is_null( value ) ) { continue; }
        std::string source;
        bool        fromIdentifier = false;
        if( jsNodeIs( value, "call_expression" ) && nodeFieldText( value, NodeField::Function, src ) == "require" )
        {
            source = jsModuleLoadTarget( value, src );
        }
        else if( jsNodeIs( value, "identifier" ) && jsNodeIs( name, "object_pattern" ) )
        {
            source         = std::string( pattern::nodeText( value, src ) );
            fromIdentifier = true;
        }
        if( source.empty() ) { continue; }
        bool any = false;
        if( jsNodeIs( name, "identifier" ) && !fromIdentifier )
        {
            emit( declarator, std::string( pattern::nodeText( name, src ) ), source, std::string( "*" ), false );
            any = true;
        }
        else if( jsNodeIs( name, "object_pattern" ) )
        {
            ChildCursor patternCursor( name );
            std::vector<TSNode> props;
            collectChildren( name, patternCursor.cur, props );
            for( TSNode prop : props )
            {
                if( jsNodeIs( prop, "shorthand_property_identifier_pattern" ) )
                {
                    std::string local( pattern::nodeText( prop, src ) );
                    emit( declarator, local, source, local, fromIdentifier );
                    any = true;
                }
                else if( jsNodeIs( prop, "pair_pattern" ) )
                {
                    const TSNode key = fieldChild( prop, NodeField::Key );
                    const TSNode val = fieldChild( prop, NodeField::Value );
                    if( jsNodeIs( key, "property_identifier" ) && jsNodeIs( val, "identifier" ) )
                    {
                        emit( declarator, std::string( pattern::nodeText( val, src ) ), source, std::string( pattern::nodeText( key, src ) ), fromIdentifier );
                        any = true;
                    }
                }
            }
        }
        if( any ) { aliasDecls.try_emplace( ts_node_start_byte( declarator ), 1 ); }
    }
}

// FE-A: add to `names` every JS/TS global (externalnames.h kJsGlobalObjectNames / kJsGlobalFunctionNames, and the names
// of the global object itself, kJsGlobalAliasNames: `var self = this` hides `self` exactly as `const JSON = …` hides
// JSON) the file spells as an identifier token — the set whose declarations the shadow walk records. One linear token
// scan; comments and strings over-include (a harmless extra name the walk then finds no declaration of).
inline void jsNoteGlobalSpellings( TSNode root, std::string_view src, HashMap<std::string, char>& names )
{
    const std::uint32_t end = std::min<std::uint32_t>( ts_node_end_byte( root ), static_cast<std::uint32_t>( src.size() ) );
    std::uint32_t at = ts_node_start_byte( root );
    while( at < end )
    {
        if( !namesplit::isIdentChar( src[ at ] ) ) { ++at; continue; }
        const std::uint32_t start = at;
        while( at < end && namesplit::isIdentChar( src[ at ] ) ) { ++at; }
        const std::string_view token = src.substr( start, at - start );
        if( externalnames::jsGlobalKindOf( token ) != externalnames::JsGlobal::None ) { names.try_emplace( std::string( token ), 1 ); }
    }
}

// FE-A: Go import specs as MODULE ALIASES (model.h LocalBindKind::ModuleAlias): `import c "x/y"` → ( c, x/y ), `import
// "x/y"` → ( the package name the path implies, x/y ), `import . "x/y"` → ( ".", x/y ); a blank import binds nothing. The
// implied name is the path's last element with a trailing major version (`/v2`, `.v3`) and a `go-` prefix or `-go`
// suffix dropped — the convention, not the package clause, which lives outside the tree: a package that names itself
// otherwise is simply not recognised (graph.h then leaves its calls to the ladder, as before).
inline std::string goImpliedPackageName( std::string_view path )
{
    std::string_view last = path;
    std::size_t      cut  = last.rfind( '/' );
    std::string_view rest = cut == std::string_view::npos ? std::string_view{} : last.substr( 0, cut );
    last = cut == std::string_view::npos ? last : last.substr( cut + 1 );
    const auto isMajor = []( std::string_view s ) { return s.size() >= 2 && s[ 0 ] == 'v' && std::all_of( s.begin() + 1, s.end(), []( char c ) { return c >= '0' && c <= '9'; } ); };
    if( isMajor( last ) && !rest.empty() )
    {
        const std::size_t prev = rest.rfind( '/' );
        last = prev == std::string_view::npos ? rest : rest.substr( prev + 1 );
    }
    if( const std::size_t dot = last.rfind( '.' ); dot != std::string_view::npos && isMajor( last.substr( dot + 1 ) ) ) { last = last.substr( 0, dot ); }
    if( last.starts_with( "go-" ) ) { last.remove_prefix( 3 ); }
    if( last.ends_with( "-go" ) ) { last.remove_suffix( 3 ); }
    return std::string( last );
}

inline void captureGoImportFacts( TSNode root, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( lang != Lang::Go ) { return; }
    ChildCursor cursor( root );
    std::vector<TSNode> pending;
    collectChildren( root, cursor.cur, pending );
    std::erase_if( pending, []( TSNode n ) { return !jsNodeIs( n, "import_declaration" ); } );
    while( !pending.empty() )
    {
        const TSNode node = pending.back();
        pending.pop_back();
        if( jsNodeIs( node, "import_declaration" ) || jsNodeIs( node, "import_spec_list" ) )
        {
            ChildCursor childCursor( node );
            std::vector<TSNode> nested;
            collectChildren( node, childCursor.cur, nested );
            for( TSNode child : nested ) { pending.push_back( child ); }
            continue;
        }
        if( !jsNodeIs( node, "import_spec" ) ) { continue; }
        const TSNode pathNode = fieldChild( node, NodeField::Path );
        if( ts_node_is_null( pathNode ) ) { continue; }
        std::string_view written = pattern::nodeText( pathNode, src );   // "x/y" or `x/y`, one delimiter pair
        if( written.size() < 2 || written.front() != written.back() || ( written.front() != '"' && written.front() != '`' ) ) { continue; }
        std::string path( written.substr( 1, written.size() - 2 ) );
        if( path.empty() ) { continue; }
        const TSNode nameNode = fieldChild( node, NodeField::Name );
        std::string  local    = ts_node_is_null( nameNode ) ? goImpliedPackageName( path ) : std::string( pattern::nodeText( nameNode, src ) );
        if( local.empty() || local == "_" ) { continue; }
        RawBind bind;
        bind.fileId       = fileId;
        bind.lang         = lang;
        bind.startByte    = ts_node_start_byte( node );
        bind.kind         = LocalBindKind::ModuleAlias;
        bind.var          = std::move( local );
        bind.typeName     = std::move( path );
        bind.importedName = "*";
        binds.push_back( std::move( bind ) );
    }
}

// The names a JS/TS declaration node binds (a pattern for jsPatternNames) and the scope node they are visible in: a
// function's or catch clause's parameters, a `for (x in/of …)` head, a `let`/`const`/`var` declarator (a `var` reaches its
// function, the others their block). Null fields when `node` declares nothing this way; hoisted function and class
// declarations are jsHoistedDeclScope's. Shared by the import-shadow walk and the FC3 rebind walk, so one rule decides
// which binding a name at a byte refers to.
struct JsDecl
{
    TSNode binding{};
    TSNode scope{};
};

inline JsDecl jsDeclarationOf( TSNode node )
{
    TSNode binding{};
    TSNode scope{};
    if( jsFunctionScope( node ) )
    {
        binding = fieldChild( node, NodeField::Parameters );
        if( ts_node_is_null( binding ) ) { binding = fieldChild( node, NodeField::Parameter ); }
        scope = node;
    }
    else if( jsNodeIs( node, "catch_clause" ) )
    {
        binding = fieldChild( node, NodeField::Parameter );
        scope = node;
    }
    else if( jsNodeIs( node, "for_in_statement" ) )
    {
        binding = fieldChild( node, NodeField::Left );
        scope = node;
        if( jsHasToken( node, "var" ) )
        {
            for( scope = ts_node_parent( node ); !ts_node_is_null( scope ); scope = ts_node_parent( scope ) )
            {
                if( jsFunctionScope( scope ) || jsNodeIs( scope, "program" ) ) { break; }
            }
        }
    }
    else if( jsNodeIs( node, "variable_declarator" ) )
    {
        binding = fieldChild( node, NodeField::Name );
        const bool isVar = jsNodeIs( ts_node_parent( node ), "variable_declaration" );
        for( scope = ts_node_parent( node ); !ts_node_is_null( scope ); scope = ts_node_parent( scope ) )
        {
            if( jsFunctionScope( scope ) || jsNodeIs( scope, "program" )
                || ( !isVar && ( jsNodeIs( scope, "statement_block" ) || jsNodeIs( scope, "for_statement" )
                                || jsNodeIs( scope, "for_in_statement" ) || jsNodeIs( scope, "switch_body" ) ) ) ) { break; }
        }
    }
    if( ( jsNodeIs( node, "variable_declarator" ) || jsNodeIs( node, "for_in_statement" ) )
        && !ts_node_is_null( scope ) && jsFunctionScope( scope ) )
    {
        scope = fieldChild( scope, NodeField::Body );
    }
    return { binding, scope };
}

// A hoisted declaration's own NAME node and the scope it binds that name in (`function f(){}` / `class C {}` → the
// enclosing block or program; a named function or class EXPRESSION → the expression itself). Null name otherwise.
inline JsDecl jsHoistedDeclScope( TSNode node )
{
    if( !( jsNodeIs( node, "function_declaration" ) || jsNodeIs( node, "generator_function_declaration" ) || jsNodeIs( node, "class_declaration" )
           || jsNodeIs( node, "function_expression" ) || jsNodeIs( node, "generator_function" ) || jsNodeIs( node, "class" )
           || jsNodeIs( node, "abstract_class_declaration" ) ) )
    {
        return {};
    }
    const TSNode nameNode = fieldChild( node, NodeField::Name );
    if( ts_node_is_null( nameNode ) ) { return {}; }
    const bool expression = jsNodeIs( node, "function_expression" ) || jsNodeIs( node, "generator_function" ) || jsNodeIs( node, "class" );
    TSNode parent = expression ? node : ts_node_parent( node );
    while( !expression && !ts_node_is_null( parent ) && !jsNodeIs( parent, "statement_block" ) && !jsNodeIs( parent, "program" ) )
    { parent = ts_node_parent( parent ); }
    return { nameNode, parent };
}

// Lane js-def-naming: the stem a JS file's bare `module.exports = <anonymous fn>` is named by (ingest_sidecap.h captureTagsFacts,
// ingest_names.h isCjsModuleExportsItself): the Markdown file node's rule, `std::filesystem::path( path ).stem()`; "" for every other
// language, which has no such definition (and pays no allocation).
inline std::string cjsExportStem( Lang lang, std::string_view path )
{
    return lang == Lang::JavaScript ? std::filesystem::path( path ).stem().string() : std::string();
}

// Lane js-def-naming: one LocalBindKind::JsObjectLiteral per declarator of a module-scope `const|let|var NAME = { … }` (model.h),
// the literal's binding name over its own span — the name its members' owner has, which the index stores nowhere else.
inline void recordJsObjectLiterals( TSNode decl, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    ChildCursor         cursor( decl );
    std::vector<TSNode> declarators;
    collectChildren( decl, cursor.cur, declarators );
    for( const TSNode variable : declarators )
    {
        const TSNode name  = jsNodeIs( variable, "variable_declarator" ) ? fieldChild( variable, NodeField::Name ) : TSNode{};
        const TSNode value = ts_node_is_null( name ) ? TSNode{} : fieldChild( variable, NodeField::Value );
        if( !jsNodeIs( name, "identifier" ) || !jsNodeIs( value, "object" ) )
        {
            continue;
        }
        RawBind bind;
        bind.fileId    = fileId;
        bind.lang      = lang;
        bind.startByte = ts_node_start_byte( variable );
        bind.kind      = LocalBindKind::JsObjectLiteral;
        bind.var       = std::string( pattern::nodeText( name, src ) );
        bind.spanStart = ts_node_start_byte( value );
        bind.spanEnd   = ts_node_end_byte( value );
        binds.push_back( std::move( bind ) );
    }
}

inline void captureJsImportFacts( TSNode root, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( lang != Lang::TypeScript && lang != Lang::JavaScript ) { return; }
    ChildCursor cursor( root );
    std::vector<TSNode> children;
    collectChildren( root, cursor.cur, children );
    HashMap<std::string, char> imported;
    imported.reserve( children.size() );
    HashMap<std::uint32_t, char> aliasDecls;   // FE-A: start bytes of the declarators that ARE a ModuleAlias — never their own shadow
    const auto record = [ & ]( TSNode node, LocalBindKind kind, std::string name, TSNode scope )
    {
        RawBind bind;
        bind.fileId = fileId;
        bind.lang = lang;
        bind.startByte = ts_node_start_byte( node );
        bind.kind = kind;
        bind.var = std::move( name );
        if( !ts_node_is_null( scope ) )
        {
            bind.spanStart = ts_node_start_byte( scope );
            bind.spanEnd = ts_node_end_byte( scope );
        }
        binds.push_back( std::move( bind ) );
    };
    for( TSNode stmt : children )
    {
        if( jsNodeIs( stmt, "import_statement" ) )
        {
            TSNode source = fieldChild( stmt, NodeField::Source );
            if( ts_node_is_null( source ) ) { continue; }
            const std::string module = importSpecifierText( source, src );
            std::vector<TSNode> pending{ stmt };
            while( !pending.empty() )
            {
                TSNode node = pending.back();
                pending.pop_back();
                const bool isDefault = jsNodeIs( node, "identifier" ) && jsNodeIs( ts_node_parent( node ), "import_clause" );
                if( isDefault || jsNodeIs( node, "import_specifier" ) )
                {
                    TSNode name = isDefault ? node : fieldChild( node, NodeField::Name );
                    TSNode alias = isDefault ? node : fieldChild( node, NodeField::Alias );
                    if( ts_node_is_null( alias ) ) { alias = name; }
                    if( !jsNodeIs( alias, "identifier" ) ) { continue; }
                    std::string local( pattern::nodeText( alias, src ) );
                    imported.try_emplace( local, 1 );
                    record( stmt, LocalBindKind::JsImport, std::move( local ), {} );
                    binds.back().typeName = module;
                    if( !jsHasToken( stmt, "type" ) && !jsHasToken( node, "type" ) && jsNodeIs( name, "identifier" ) )
                    {
                        binds.back().importedName = isDefault ? "default" : std::string( pattern::nodeText( name, src ) );
                    }
                    else if( !isDefault && jsNodeIs( name, "identifier" ) && pattern::nodeText( name, src ) == pattern::nodeText( alias, src ) )
                    {
                        // lane receiver-fixes (TS-FIELD-SELF): a TYPE-only `import type { T }` binds no value (importedName stays "", so no
                        // call pins through it), but its local IS the module's export name: graph.h buildJsImportTables reads it as not
                        // renamed, so an interface T a field or local is typed as finds its module (receiverevidence.h importedTypeClass)
                        binds.back().isFromAssignment = true;
                    }
                }
                else if( jsNodeIs( node, "namespace_import" ) && !jsHasToken( stmt, "type" ) )
                {
                    // FE-A: `import * as ns from 'm'` binds the MODULE; graph.h FalseEdgeRules reads `ns.f()` through it
                    ChildCursor nsCursor( node );
                    std::vector<TSNode> nsKids;
                    collectChildren( node, nsCursor.cur, nsKids );
                    for( TSNode kid : nsKids )
                    {
                        if( !jsNodeIs( kid, "identifier" ) ) { continue; }
                        std::string local( pattern::nodeText( kid, src ) );
                        imported.try_emplace( local, 1 );
                        record( stmt, LocalBindKind::ModuleAlias, std::move( local ), {} );
                        binds.back().typeName     = module;
                        binds.back().importedName = "*";
                    }
                }
                else if( jsNodeIs( node, "import_statement" ) || jsNodeIs( node, "import_clause" ) || jsNodeIs( node, "named_imports" ) )
                {
                    ChildCursor childCursor( node );
                    std::vector<TSNode> nested;
                    collectChildren( node, childCursor.cur, nested );
                    for( TSNode child : nested ) { pending.push_back( child ); }
                }
            }
        }
        else if( jsNodeIs( stmt, "lexical_declaration" ) || jsNodeIs( stmt, "variable_declaration" ) )
        {
            recordJsObjectLiterals( stmt, lang, fileId, src, binds );
            captureJsModuleAliases( stmt, src, aliasDecls, [ & ]( TSNode declarator, std::string local, std::string source, std::string member, bool fromIdentifier )
            {
                imported.try_emplace( local, 1 );
                record( declarator, LocalBindKind::ModuleAlias, std::move( local ), {} );
                binds.back().typeName         = std::move( source );
                binds.back().importedName     = std::move( member );
                binds.back().isFromAssignment = fromIdentifier;
            } );
        }
        else if( jsNodeIs( stmt, "export_statement" ) )
        {
            TSNode decl = fieldChild( stmt, NodeField::Declaration );
            if( jsHasToken( stmt, "default" ) )
            {
                TSNode value = fieldChild( stmt, NodeField::Value );
                TSNode name{};
                if( !ts_node_is_null( decl ) ) { name = fieldChild( decl, NodeField::Name ); }
                record( stmt, LocalBindKind::JsExport, "default", root );
                if( jsNodeIs( value, "identifier" ) && jsModuleBindingCount( root, pattern::nodeText( value, src ), src ) == 1 )
                {
                    binds.back().importedName = std::string( pattern::nodeText( value, src ) );
                }
                else if( jsNodeIs( decl, "function_declaration" ) || jsNodeIs( decl, "generator_function_declaration" )
                         || jsNodeIs( decl, "class_declaration" ) || jsNodeIs( decl, "abstract_class_declaration" ) )
                {
                    if( ( jsNodeIs( name, "identifier" ) || jsNodeIs( name, "type_identifier" ) )
                        && jsModuleBindingCount( root, pattern::nodeText( name, src ), src ) == 1 )
                    {
                        binds.back().spanStart = ts_node_start_byte( decl );
                        binds.back().spanEnd = ts_node_end_byte( decl );
                        binds.back().importedName = std::string( pattern::nodeText( name, src ) );
                    }
                }
                continue;
            }
            if( ts_node_is_null( decl ) )
            {
                // Clause form. The scope is the whole PROGRAM: a clause exports a module-scope binding and
                // the declaration it names may sit anywhere in the file (hoisted, or simply above).
                // importedName is spelled even when it equals `var` — it is what buildJsImportTables matches
                // a DEFINITION by, and it is what keeps two specifiers of one clause (which share this
                // statement's start byte) distinguishable to emitBindings' total order.
                for( const auto& [ exportName, localName ] : jsExportClauseNames( stmt, src ) )
                {
                    record( stmt, LocalBindKind::JsExport, exportName, root );
                    if( exportName != "default" || jsModuleBindingCount( root, localName, src ) == 1 )
                    {
                        binds.back().importedName = localName;
                    }
                }
                continue;
            }
            TSNode name = fieldChild( decl, NodeField::Name );
            if( jsNodeIs( decl, "function_declaration" ) || jsNodeIs( decl, "generator_function_declaration" )
                || jsNodeIs( decl, "class_declaration" ) || jsNodeIs( decl, "abstract_class_declaration" ) )
            {
                record( stmt, LocalBindKind::JsExport, std::string( pattern::nodeText( name, src ) ), decl );
            }
            else if( jsNodeIs( decl, "lexical_declaration" ) || jsNodeIs( decl, "variable_declaration" ) )
            {
                recordJsObjectLiterals( decl, lang, fileId, src, binds );
                ChildCursor declCursor( decl );
                std::vector<TSNode> declarators;
                collectChildren( decl, declCursor.cur, declarators );
                for( TSNode variable : declarators )
                {
                    if( !jsNodeIs( variable, "variable_declarator" ) ) { continue; }
                    TSNode value = fieldChild( variable, NodeField::Value );
                    if( !jsNodeIs( value, "arrow_function" ) && !jsNodeIs( value, "function_expression" ) ) { continue; }
                    TSNode binding = fieldChild( variable, NodeField::Name );
                    if( jsNodeIs( binding, "identifier" ) )
                    {
                        record( stmt, LocalBindKind::JsExport, std::string( pattern::nodeText( binding, src ) ), decl );
                    }
                }
            }
        }
    }
    // FE-A: a declaration spelled like a JS/TS global (`const JSON = …`, a parameter `fetch`) hides the global the same way
    // it hides an import, and graph.h FalseEdgeRules reads both through these JsShadow records. Only names the file spells
    // as an identifier join, so a file that never says `JSON` pays nothing for it.
    jsNoteGlobalSpellings( root, src, imported );
    if( imported.empty() ) { return; }

    // Imports are module-scoped. Record matching declarations' lexical spans so nested closures inherit
    // shadows too. We deliberately omit local-call inference here; a shadow may resolve to no edge.
    std::vector<TSNode> pending{ root };
    while( !pending.empty() )
    {
        TSNode node = pending.back();
        pending.pop_back();
        // an alias declarator is never its own shadow
        const bool   isAlias = jsNodeIs( node, "variable_declarator" ) && aliasDecls.find( ts_node_start_byte( node ) ) != aliasDecls.end();
        const JsDecl d       = isAlias ? JsDecl{} : jsDeclarationOf( node );
        for( std::string name : jsPatternNames( d.binding, src ) )
        {
            if( imported.find( name ) != imported.end() ) { record( node, LocalBindKind::JsShadow, std::move( name ), d.scope ); }
        }
        // Hoisted local function/class declarations also hide imports, independently of their parameters.
        if( const JsDecl hoisted = jsHoistedDeclScope( node ); !ts_node_is_null( hoisted.binding ) )
        {
            std::string name( pattern::nodeText( hoisted.binding, src ) );
            if( imported.find( name ) != imported.end() ) { record( node, LocalBindKind::JsShadow, std::move( name ), hoisted.scope ); }
        }
        ChildCursor childCursor( node );
        std::vector<TSNode> nested;
        collectChildren( node, childCursor.cur, nested );
        for( TSNode child : nested ) { pending.push_back( child ); }
    }
}


// FC3: does the value written to `name` keep the name — the identifier `name` itself, or a member named `name`
// (`util.equal` → `equal`, `require( 'e' ).Eng` → `Eng`)? Such a write rebinds the name to what the same SPELLING
// names, which is the name ladder's own reading of the call, so it is not a rebinding the binder must refuse. A null
// value (`+=`, `++`, a `for…of` head) never keeps it.
inline bool jsValueKeepsName( TSNode value, std::string_view name, std::string_view src )
{
    while( jsNodeIs( value, "parenthesized_expression" ) || jsNodeIs( value, "as_expression" ) || jsNodeIs( value, "satisfies_expression" )
           || jsNodeIs( value, "non_null_expression" ) )
    {
        if( ts_node_named_child_count( value ) == 0 ) { return false; }
        value = ts_node_named_child( value, 0 );
    }
    if( jsNodeIs( value, "identifier" ) ) { return pattern::nodeText( value, src ) == name; }
    if( jsNodeIs( value, "member_expression" ) )
    {
        const TSNode property = fieldChild( value, NodeField::Property );
        return !ts_node_is_null( property ) && pattern::nodeText( property, src ) == name;
    }
    return false;
}

// FC3: the value an object LITERAL gives property `key` (`{ key: v }`, or the shorthand `{ key }` → that identifier);
// null when the literal has no such plain property (a spread or a computed key may still supply one: the caller then
// reads the name as not kept).
inline TSNode jsObjectLiteralValue( TSNode object, std::string_view key, std::string_view src )
{
    for( std::uint32_t i = 0; i < ts_node_named_child_count( object ); ++i )
    {
        const TSNode prop = ts_node_named_child( object, i );
        if( jsNodeIs( prop, "shorthand_property_identifier" ) && pattern::nodeText( prop, src ) == key ) { return prop; }
        if( jsNodeIs( prop, "pair" ) )
        {
            const TSNode k = fieldChild( prop, NodeField::Key );
            if( jsNodeIs( k, "property_identifier" ) && pattern::nodeText( k, src ) == key ) { return fieldChild( prop, NodeField::Value ); }
        }
    }
    return {};
}

// FC3: every name a write to `target` (an identifier or a destructuring pattern) assigns, with whether its new value
// keeps the name (jsValueKeepsName), handed to `emit( name, keeps )`. `value` is the right-hand side, null when unknown.
// An object pattern reads each property by its KEY: from an object literal, that property's own value; from anything
// else, a member of that name (`({ css } = getEnv())` keeps `css`). A default (`{ x = d }`), a rest element and every
// array-pattern slot never keep the name: which value lands there is not read here. Nested patterns are walked with an
// explicit stack of frames (depth-first, in source order), never by recursion: a file nests patterns as deep as it likes.
template <class Emit>
inline void jsNoteRebindingWrites( TSNode target, TSNode value, std::string_view src, Emit&& emit )
{
    struct Frame { TSNode target; TSNode value; std::uint32_t next; bool literal; };
    std::vector<Frame> stack;
    // one target/value pair: an identifier or a non-object pattern emits at once, an object pattern opens a frame
    const auto enter = [ & ]( TSNode t, TSNode v )
    {
        while( jsNodeIs( t, "parenthesized_expression" ) && ts_node_named_child_count( t ) == 1 ) { t = ts_node_named_child( t, 0 ); }
        while( jsNodeIs( v, "parenthesized_expression" ) && ts_node_named_child_count( v ) == 1 ) { v = ts_node_named_child( v, 0 ); }
        if( jsNodeIs( t, "identifier" ) )
        {
            const std::string_view name = pattern::nodeText( t, src );
            emit( std::string( name ), jsValueKeepsName( v, name, src ) );
        }
        else if( jsNodeIs( t, "object_pattern" ) ) { stack.push_back( { t, v, 0, jsNodeIs( v, "object" ) } ); }
        else { for( std::string& name : jsPatternNames( t, src ) ) { emit( std::move( name ), false ); } }   // array, rest, …
    };
    enter( target, value );
    while( !stack.empty() )
    {
        Frame& frame = stack.back();
        if( frame.next >= ts_node_named_child_count( frame.target ) ) { stack.pop_back(); continue; }
        const TSNode prop    = ts_node_named_child( frame.target, frame.next++ );
        const TSNode object  = frame.value;
        const bool   literal = frame.literal;   // copied: `enter` below may grow the stack and move `frame`
        if( jsNodeIs( prop, "shorthand_property_identifier_pattern" ) )
        {
            const std::string_view name = pattern::nodeText( prop, src );
            emit( std::string( name ), literal ? jsValueKeepsName( jsObjectLiteralValue( object, name, src ), name, src ) : true );
        }
        else if( jsNodeIs( prop, "pair_pattern" ) )
        {
            const TSNode key = fieldChild( prop, NodeField::Key );
            const TSNode sub = fieldChild( prop, NodeField::Value );
            if( !jsNodeIs( key, "property_identifier" ) )
            {
                for( std::string& name : jsPatternNames( sub, src ) ) { emit( std::move( name ), false ); }   // a computed key
                continue;
            }
            const std::string_view keyText = pattern::nodeText( key, src );
            if( jsNodeIs( sub, "identifier" ) )
            {
                const std::string_view name = pattern::nodeText( sub, src );
                emit( std::string( name ), literal ? jsValueKeepsName( jsObjectLiteralValue( object, keyText, src ), name, src ) : keyText == name );
            }
            else
            {
                enter( sub, literal ? jsObjectLiteralValue( object, keyText, src ) : TSNode{} );
            }
        }
        else
        {
            for( std::string& name : jsPatternNames( prop, src ) ) { emit( std::move( name ), false ); }   // `{ x = d }`, `...rest`
        }
    }
}

// FC3 (T1 class 14 ALIAS-THROUGH-ASSIGNMENT): a JS/TS binding that is WRITTEN after its declaration no longer names what
// it was declared as — `let { Eng, Foo } = require( 'e' ); Eng = Foo; new Eng()` builds a Foo — so the call binder must not
// read its declaration (or its spelling) as the target. Records one LocalBindKind::JsRebind per written binding (model.h):
// at the DECLARATION the write resolves to — the innermost one in scope at the write, by jsDeclarationOf /
// jsHoistedDeclScope, the import-shadow walk's own rule — spanning that declaration's WHOLE scope: byte order is not run
// order (a closure may run after the write, a loop body runs again), so every call by the name in that scope is undecided,
// conditional writes included. A write the file declares nowhere (an implicit global, CommonJS `exports`) spans the program.
// Writes that throw record nothing: an ES import binding, a `const`, a named function/class expression's own name.
// A second `var x = …` / `function x` in one scope is a write too. A write whose value KEEPS the name (`equal =
// util.equal`, `({ css } = getEnv())`: jsValueKeepsName) is no rebinding when its declaration binds NO value (`var x;`,
// `let x;`, undeclared) — the declare-then-assign test-file idiom (`var Environment; … Environment = require( … ).Environment`)
// keeps its edges. Over a declaration that already pinned a definition (`let { Eng } = require( 'a' )`, `class Eng`) the
// spelling proves nothing: the new value may be another module's, so it is a write. Only names the file CALLS (`x()`,
// `new x()`, `x.m()`) are recorded, so a loop counter's `i++` costs nothing downstream.
inline void captureJsRebindFacts( TSNode root, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( lang != Lang::TypeScript && lang != Lang::JavaScript ) { return; }
    struct Write { std::string name; std::uint32_t at; bool keeping = false; };
    std::vector<Write>                  writes;    // every write; `keeping` ones (jsValueKeepsName) count only beside a declaration with no initializer
    HashMap<std::string, char>          called;
    HashMap<std::string, std::vector<Write>> hoisted;   // "<scope start>#name" → its initializing var / function declarations
    const auto noteWrites = [ & ]( TSNode target, TSNode value, std::uint32_t at )
    {
        jsNoteRebindingWrites( target, value, src, [ & ]( std::string name, bool keeps ) { writes.push_back( { std::move( name ), at, keeps } ); } );
    };
    const auto noteHoisted = [ & ]( TSNode scope, std::string name, bool keeps, std::uint32_t at )
    {
        if( ts_node_is_null( scope ) ) { return; }
        hoisted[ std::to_string( ts_node_start_byte( scope ) ) + "#" + name ].push_back( { keeps ? std::string() : name, at } );
    };
    const auto calleeName = [ & ]( TSNode callee )
    {
        while( jsNodeIs( callee, "member_expression" ) ) { callee = fieldChild( callee, NodeField::Object ); }
        if( jsNodeIs( callee, "identifier" ) ) { called.try_emplace( std::string( pattern::nodeText( callee, src ) ), 1 ); }
    };
    std::vector<TSNode> pending{ root };
    while( !pending.empty() )
    {
        const TSNode node = pending.back();
        pending.pop_back();
        const std::uint32_t at = ts_node_start_byte( node );
        if( jsNodeIs( node, "assignment_expression" ) )
        {
            noteWrites( fieldChild( node, NodeField::Left ), fieldChild( node, NodeField::Right ), at );
        }
        else if( jsNodeIs( node, "augmented_assignment_expression" ) )
        {
            noteWrites( fieldChild( node, NodeField::Left ), TSNode{}, at );   // `x += v`: a new value, whatever v is
        }
        else if( jsNodeIs( node, "update_expression" ) )
        {
            noteWrites( fieldChild( node, NodeField::Argument ), TSNode{}, at );
        }
        else if( jsNodeIs( node, "for_in_statement" ) && !jsHasToken( node, "var" ) && !jsHasToken( node, "let" ) && !jsHasToken( node, "const" ) )
        {
            noteWrites( fieldChild( node, NodeField::Left ), TSNode{}, at );   // `for ( x of xs )` assigns an existing binding
        }
        else if( jsNodeIs( node, "call_expression" ) )
        {
            calleeName( fieldChild( node, NodeField::Function ) );
        }
        else if( jsNodeIs( node, "new_expression" ) )
        {
            calleeName( fieldChild( node, NodeField::Constructor ) );
        }
        else if( jsNodeIs( node, "variable_declarator" ) && jsNodeIs( ts_node_parent( node ), "variable_declaration" )
                 && !ts_node_is_null( fieldChild( node, NodeField::Value ) ) )
        {
            const JsDecl d = jsDeclarationOf( node );
            jsNoteRebindingWrites( d.binding, fieldChild( node, NodeField::Value ), src,
                                   [ & ]( std::string name, bool keeps ) { noteHoisted( d.scope, std::move( name ), keeps, at ); } );
        }
        else if( jsNodeIs( node, "function_declaration" ) || jsNodeIs( node, "generator_function_declaration" ) )
        {
            const JsDecl d = jsHoistedDeclScope( node );   // `function f` binds f to itself: the name's own definition
            if( !ts_node_is_null( d.binding ) ) { noteHoisted( d.scope, std::string( pattern::nodeText( d.binding, src ) ), true, at ); }
        }
        ChildCursor childCursor( node );
        std::vector<TSNode> nested;
        collectChildren( node, childCursor.cur, nested );
        for( TSNode child : nested ) { pending.push_back( child ); }
    }
    for( auto& [ key, decls ] : hoisted )   // one `var` binding declared twice: every initializer is a write to it
    {
        if( decls.size() < 2 ) { continue; }
        const std::string name = key.substr( key.find( '#' ) + 1 );
        for( const Write& d : decls ) { if( !d.name.empty() ) { writes.push_back( { name, d.at } ); } }
    }
    std::erase_if( writes, [ & ]( const Write& w ) { return !called.contains( w.name ); } );
    if( writes.empty() ) { return; }
    HashMap<std::string, char> written;
    for( const Write& w : writes ) { written.try_emplace( w.name, 1 ); }

    // The declarations of the written names: the node that declares, its scope, and whether a write to it throws.
    struct Decl { std::string name; TSNode node; std::uint32_t start; std::uint32_t end; bool immutable; bool initialized; };
    std::vector<Decl> decls;
    const auto noteDecl = [ & ]( std::string name, TSNode node, TSNode scope, bool immutable )
    {
        if( ts_node_is_null( scope ) || !written.contains( name ) ) { return; }
        // only `var x;` / `let x;` binds no value: a parameter, a `for` head, a class or function declaration, an import and every
        // declarator with an initializer already pins a definition, which a write that "keeps the name" may not silently replace
        const bool initialized = !( jsNodeIs( node, "variable_declarator" ) && ts_node_is_null( fieldChild( node, NodeField::Value ) ) );
        decls.push_back( { std::move( name ), node, ts_node_start_byte( scope ), ts_node_end_byte( scope ), immutable, initialized } );
    };
    pending.assign( 1, root );
    while( !pending.empty() )
    {
        const TSNode node = pending.back();
        pending.pop_back();
        if( jsNodeIs( node, "import_specifier" ) || jsNodeIs( node, "namespace_import" )
            || ( jsNodeIs( node, "identifier" ) && jsNodeIs( ts_node_parent( node ), "import_clause" ) ) )
        {
            TSNode local = node;
            if( jsNodeIs( node, "import_specifier" ) )
            {
                local = fieldChild( node, NodeField::Alias );
                if( ts_node_is_null( local ) ) { local = fieldChild( node, NodeField::Name ); }
            }
            else if( jsNodeIs( node, "namespace_import" ) )
            {
                local = ts_node_named_child_count( node ) > 0 ? ts_node_named_child( node, ts_node_named_child_count( node ) - 1 ) : TSNode{};
            }
            if( jsNodeIs( local, "identifier" ) ) { noteDecl( std::string( pattern::nodeText( local, src ) ), node, root, true ); }   // an import binding is read-only
        }
        else if( !( jsNodeIs( node, "for_in_statement" ) && !jsHasToken( node, "var" ) && !jsHasToken( node, "let" ) && !jsHasToken( node, "const" ) ) )
        {
            const JsDecl d = jsDeclarationOf( node );
            if( !ts_node_is_null( d.binding ) )
            {
                const TSNode statement = ts_node_parent( node );
                const bool   constant  = jsNodeIs( node, "variable_declarator" ) && jsNodeIs( statement, "lexical_declaration" ) && jsHasToken( statement, "const" );
                for( std::string& name : jsPatternNames( d.binding, src ) ) { noteDecl( std::move( name ), node, d.scope, constant ); }
            }
            if( const JsDecl h = jsHoistedDeclScope( node ); !ts_node_is_null( h.binding ) )
            {
                const bool expression = jsNodeIs( node, "function_expression" ) || jsNodeIs( node, "generator_function" ) || jsNodeIs( node, "class" );
                noteDecl( std::string( pattern::nodeText( h.binding, src ) ), node, h.scope, expression );   // an expression's own name is read-only
            }
        }
        ChildCursor childCursor( node );
        std::vector<TSNode> nested;
        collectChildren( node, childCursor.cur, nested );
        for( TSNode child : nested ) { pending.push_back( child ); }
    }

    HashMap<std::string, char> recorded;   // "<declaration start>#name": one record per written binding
    for( const Write& w : writes )
    {
        const Decl* best = nullptr;
        for( const Decl& d : decls )
        {
            if( d.name != w.name || w.at < d.start || w.at >= d.end ) { continue; }
            if( best == nullptr || d.end - d.start < best->end - best->start
                || ( d.end - d.start == best->end - best->start && ts_node_start_byte( d.node ) < ts_node_start_byte( best->node ) ) ) { best = &d; }
        }
        if( best != nullptr && best->immutable ) { continue; }   // writing it throws: the declared target stands
        // pinned: the declaration already bound a definition (`let { Eng } = require( 'a' )`, `class Eng`, a parameter, a `for` head,
        // an import) — as opposed to `var x;` / `let x;` / an undeclared name, which hold nothing the write could replace
        const bool pinned = best != nullptr
            && std::any_of( decls.begin(), decls.end(), [ & ]( const Decl& d )
                            { return d.name == w.name && d.start == best->start && d.end == best->end && d.initialized; } );
        // `Eng = require( 'b' ).Eng` over `let Eng;` is the declare-then-assign idiom: the spelling names what it named. Over a
        // pinned declaration the spelling is not the proof — the new value may be another module's: a write, as any other
        if( w.keeping && !pinned ) { continue; }
        const TSNode node = best != nullptr ? best->node : root;
        if( !recorded.try_emplace( std::to_string( ts_node_start_byte( node ) ) + "#" + w.name, 1 ).second ) { continue; }
        RawBind bind;
        bind.fileId    = fileId;
        bind.lang      = lang;
        // the file's END, which no definition's span holds: the record has no owner (fromSymbol kNoNode), so no reader
        // keyed on (fromSymbol, var) takes it for a local of a function — the binding's scope is the span below
        bind.startByte = ts_node_end_byte( root );
        bind.kind      = LocalBindKind::JsRebind;
        bind.var       = w.name;
        bind.isFromAssignment = pinned;   // graph.h: a MEMBER call through the name is undecided only when a pinned declaration was replaced
        bind.spanStart = best != nullptr ? best->start : ts_node_start_byte( root );
        bind.spanEnd   = best != nullptr ? best->end : ts_node_end_byte( root );
        binds.push_back( std::move( bind ) );
    }
}
} // namespace
} // namespace rw
