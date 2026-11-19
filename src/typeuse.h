#pragma once
#include "infra/emit.h"   // house rule: every header that may grow an emitter starts from THE emitter
#include "infra/sortutil.h"   // sortUnique
// typeuse.h — L7 type-use impact: the symbols that NAME a type, read by the parser, so --impact of a class / struct /
// named type / interface starts its walk from them and not from call edges alone.
//
// THE DEFECT. --impact walks CALL edges into SYM (graph.h transitiveCallersDepth). A struct has no callers, so
// `--impact=grid_cell` on a C tree answered reaches="0" while 32 files declare, copy or access the struct; a TS class
// reached its constructor callers but never the file that defines it, nor a function that only takes it as a parameter.
//
// THE MECHANISM. One structural query per language (kTypeMentionRows, DATA rows — no Lang:: branch in the walk) finds
// every node that spells SYM's name AS A TYPE: a declaration, a parameter, a field, a return type, a base or implements
// clause, a template argument; for TS/JS also the class operand of `instanceof` and `extends`. The query runs through
// the shared --match walk (ingest.h astQueryGrouped), restricted to files whose bytes contain the name (mustContain —
// a file that never spells it cannot hold a node spelling it). Each hit maps to its innermost indexed definition
// (flipimpact.h innermostAtLine, the shared line → def lookup); that definition is a TYPE USER, the walk's first hop.
// A hit outside every definition (a file-scope declaration, a prototype the index does not keep) names its FILE.
//
// WHAT IT IS NOT. A mention is matched by its spelled NAME (the parser says it is a type position, not WHICH type):
// two indexed type definitions sharing the name make every row a possible namesake's (TypeUseTier::typeDefs, disclosed).
// The capture is not the --uses index: that index is built only by the rich ingest and records role=type for C++/ObjC
// alone (graphlegend.h kUsesLegend), so --impact (a lean verb) could not read it, and C — the motivating repo — is not in
// it. Languages without a row (C#, Kotlin, Swift, Ruby, PHP, Lua, Dart, Elixir, …) contribute no type users: a floor the
// legend names.
#include "model.h"
#include "graph.h"        // Graph, transitiveCallersDepth, provenCallerReach, namespaceCompatible
#include "ingest.h"       // AstQuerySpec / AstQueryGroup / astQueryGrouped — the shared structural-query walk
#include "flipimpact.h"   // buildSymbolLineIndex / innermostAtLine — the shared line → innermost-def lookup
#include "lintrules.h"    // langOfPath — the file's language, the key the rows are matched on
#include "graphlegend.h"  // ImpactRollupTypeClauses — the legend's view of the tier

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// One row per language that can spell a type mention. `node` is a tree-sitter pattern capturing the type NAME as @t;
// the query wraps it with an #eq? on SYM's name. Several rows may share a pattern (the C family); a hit counts only
// when its file's language has a row with that pattern, so a pattern that happens to compile in another grammar
// (astQueryGrouped compiles each spec for every grammar it fits) contributes nothing there.
struct TypeMentionRow
{
    Lang             lang;
    std::string_view node;
};

inline constexpr TypeMentionRow kTypeMentionRows[] = {
    { Lang::C,          "(type_identifier) @t" },   // `struct grid_cell gc;`, `struct grid_cell *gc` params, fields, casts
    { Lang::Cpp,        "(type_identifier) @t" },   // + return types, template arguments, base clauses
    { Lang::ObjC,       "(type_identifier) @t" },
    { Lang::Go,         "(type_identifier) @t" },   // params, fields, composite literals `Cell{}`, receivers `(c *Cell)`
    { Lang::Rust,       "(type_identifier) @t" },   // params, fields, `impl Cell`, `impl Trait for Cell`, struct literals
    { Lang::Java,       "(type_identifier) @t" },   // declarations, params, `new Cell()`, extends / implements
    { Lang::TypeScript, "(type_identifier) @t" },   // annotations, `implements Router`, generic arguments
    { Lang::TypeScript, "(extends_clause value: (identifier) @t)" },                               // `class S extends Base`
    { Lang::TypeScript, "(binary_expression operator: \"instanceof\" right: (identifier) @t)" },   // `e instanceof Base`
    { Lang::JavaScript, "(class_heritage (identifier) @t)" },                                       // `class S extends Base`
    { Lang::JavaScript, "(binary_expression operator: \"instanceof\" right: (identifier) @t)" },
    { Lang::Python,     "(type (identifier) @t)" },                                    // annotations: `def f( c: Cell ) -> Cell`
    { Lang::Python,     "(class_definition superclasses: (argument_list (identifier) @t))" },   // `class S( Base ):`
};

// One row per language whose generics can DECLARE a type parameter spelled like the type. `node` captures the whole
// declaring scope (a template, a generic function / struct / impl / method) and, as @t, the parameter's name; the query
// wraps it with the same #eq?. Inside that scope the name is the PARAMETER, so a mention there is not a type user (C++
// `template <class Cell> f( Cell )`, Rust `fn f<Cell>( c: Cell )`, TS `function f<Cell>`, Go `func f[Cell any]`, Java
// `<Cell> Cell f`). Matched on byte ranges, so a nested scope's own mention is shadowed exactly as the language reads it.
inline constexpr TypeMentionRow kTypeParamScopeRows[] = {
    { Lang::Cpp,        "(template_declaration parameters: (template_parameter_list [(type_parameter_declaration (type_identifier) @t) "
                        "(optional_type_parameter_declaration name: (type_identifier) @t)])) @s" },
    { Lang::Rust,       "(_ type_parameters: (type_parameters [(type_identifier) @t (constrained_type_parameter left: (type_identifier) @t)])) @s" },
    { Lang::TypeScript, "(_ type_parameters: (type_parameters (type_parameter name: (type_identifier) @t))) @s" },
    { Lang::Go,         "(_ type_parameters: (type_parameter_list (type_parameter_declaration name: (identifier) @t))) @s" },
    { Lang::Java,       "(_ type_parameters: (type_parameters (type_parameter (type_identifier) @t))) @s" },
};

// One row per language whose standard library is spelled by a path root: a type named through it (Rust `std::io::Error`,
// `core::fmt::Error`, `alloc::…`; C++ `std::vector`, `std::pmr::vector`) is the library's type, never an in-tree namesake,
// so its name segment shadows like a type parameter. Any other qualified spelling (`crate::Error`, `ns::Widget`) is still
// matched by its last segment (the legend says so).
inline constexpr TypeMentionRow kStdPathShadowRows[] = {
    { Lang::Rust, "(scoped_type_identifier path: (_) @r name: (type_identifier) @t) (#match? @r \"^(std|core|alloc)(::|$)\")" },
    { Lang::Cpp,  "(qualified_identifier scope: (namespace_identifier) @r name: [(type_identifier) @t (template_type name: (type_identifier) @t) "
                  "(qualified_identifier name: [(type_identifier) @t (template_type name: (type_identifier) @t)])]) (#eq? @r \"std\")" },
};

// One row per language whose methods live in a block that names the type in its HEADER (Rust `impl Shape for Sq {`,
// `impl Sq {`). rustfmt puts the header on its own line, which no indexed definition covers, so the mention there names no
// user; instead every definition inside the block (@s) is one: it implements or extends the type, and a change to the
// type reaches it. A header spelled through a path (`impl crate::Shape for X`) is matched only when the path is rooted at
// the crate (crate/self/super); any other path keeps its file-scope mention (the file is listed with syms="0").
inline constexpr TypeMentionRow kTypeBlockRows[] = {
    { Lang::Rust, "(impl_item trait: [(type_identifier) @t (generic_type type: (type_identifier) @t)]) @s" },
    { Lang::Rust, "(impl_item type: [(type_identifier) @t (generic_type type: (type_identifier) @t)]) @s" },
    { Lang::Rust, "(impl_item trait: [(scoped_type_identifier path: (_) @p name: (type_identifier) @t) "
                  "(generic_type type: (scoped_type_identifier path: (_) @p name: (type_identifier) @t))]) @s (#match? @p \"^(crate|self|super)(::|$)\")" },
    { Lang::Rust, "(impl_item type: [(scoped_type_identifier path: (_) @p name: (type_identifier) @t) "
                  "(generic_type type: (scoped_type_identifier path: (_) @p name: (type_identifier) @t))]) @s (#match? @p \"^(crate|self|super)(::|$)\")" },
};

// The name a type mention spells: the final segment of a definition's name (`ns::Widget` → `Widget`). Empty when that
// segment is not a plain identifier, which the #eq? literal could not carry safely — the tier then stays unarmed.
inline std::string_view typeMentionName( std::string_view name ) noexcept
{
    const std::size_t cut = name.find_last_of( ":." );
    const std::string_view seg = cut == std::string_view::npos ? name : name.substr( cut + 1 );
    const auto identChar = []( char c ) { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '$'; };
    if( seg.empty() || ( seg[0] >= '0' && seg[0] <= '9' ) || !std::all_of( seg.begin(), seg.end(), identChar ) )
    {
        return {};
    }
    return seg;
}

// The kinds a type mention can name — the SAME set graph.h namespaceCompatible admits for RefRole::Type (reused, not
// restated: a class, a struct / named type, an interface).
inline bool isTypeImpactKind( SymKind k ) noexcept
{
    return namespaceCompatible( RefRole::Type, k );
}

struct TypeUseTier
{
    bool                       armed       = false;   // at least one seed is a type definition with a spellable name
    std::vector<NodeId>        users;                 // innermost defs holding a mention; seeds excluded; ascending
    std::vector<std::uint32_t> defFiles;              // the files defining the type seeds (the rollup's d="0" rows); ascending
    std::vector<std::uint32_t> scopeFiles;            // files naming the type outside every indexed def, minus defFiles; ascending
    std::size_t                typeDefs    = 0;       // indexed type definitions (the whole corpus) sharing the spelled name
    bool                       sitesCapped = false;   // a pattern's matches hit the walk budget: users/scopeFiles are a floor
};

// The per-pattern match budget. A type named on every line of a large tree is the only way to reach it; reaching it
// is disclosed (type_capped="1"), never silent.
inline constexpr std::size_t kTypeMentionMatchBudget = 50000;   // per pattern; no flag raises it — type_capped="1" marks the floor

inline TypeUseTier typeUseTier( const IngestResult& ing, std::span<const NodeId> seeds )
{
    TypeUseTier tier;
    std::string name;
    for( const NodeId s : seeds )
    {
        if( s >= ing.symbols.size() || !isTypeImpactKind( ing.symbols[s].kind ) )
        {
            continue;
        }
        const std::string_view nm = typeMentionName( ing.symbols[s].name );
        if( nm.empty() || ( !name.empty() && nm != name ) )
        {
            continue;   // one selector spells one name; a seed spelled otherwise (a qualified alias) keeps its call walk only
        }
        name.assign( nm );
        tier.defFiles.push_back( ing.symbols[s].fileId );
    }
    if( name.empty() )
    {
        return tier;   // no type seed: the caller's walk is the plain call walk, byte-identical
    }
    tier.armed = true;
    rw::sortutil::sortUnique( tier.defFiles );
    for( const Symbol& s : ing.symbols )
    {
        tier.typeDefs += std::size_t( isTypeImpactKind( s.kind ) && typeMentionName( s.name ) == name );
    }

    // One spec per DISTINCT pattern; the spec's tag is the pattern itself, so a hit is matched back to its rows.
    // specLangs[i] holds one bit per Lang whose row names spec i's pattern — a hit counts only in those languages.
    // The type-parameter scopes and standard-library paths ride the same walk; specRole[i] marks them (their hits
    // shadow, never name a user), and the impl blocks (their hits name every definition inside the block).
    enum class SpecRole : char { Mention, Shadow, Block };
    std::vector<AstQuerySpec>  specs;
    std::vector<std::uint64_t> specLangs;
    std::vector<SpecRole>      specRole;
    static_assert( kLangCount <= 64, "specLangs keeps one bit per Lang" );
    const auto addRow = [ & ]( const TypeMentionRow& row, SpecRole role )
    {
        const auto at = std::find_if( specs.begin(), specs.end(), [ & ]( const AstQuerySpec& sp ) { return sp.tag == row.node; } );
        const std::size_t i = std::size_t( at - specs.begin() );
        if( at == specs.end() )
        {
            specs.push_back( AstQuerySpec{ "(" + std::string( row.node ) + " (#eq? @t \"" + name + "\"))", std::string( row.node ) } );
            specLangs.push_back( 0 );
            specRole.push_back( role );
        }
        specLangs[i] |= std::uint64_t( 1 ) << static_cast<unsigned>( row.lang );
    };
    for( const TypeMentionRow& row : kTypeMentionRows ) { addRow( row, SpecRole::Mention ); }
    for( const TypeMentionRow& row : kTypeParamScopeRows ) { addRow( row, SpecRole::Shadow ); }
    for( const TypeMentionRow& row : kStdPathShadowRows ) { addRow( row, SpecRole::Shadow ); }
    for( const TypeMentionRow& row : kTypeBlockRows ) { addRow( row, SpecRole::Block ); }
    AstQueryGroup group;
    group.specs       = &specs;
    group.maxMatches  = kTypeMentionMatchBudget;
    group.mustContain = name;
    const std::vector<std::vector<AstMatch>> got = astQueryGrouped( ing, { group } );
    ASSUME( got.size() == 1, "astQueryGrouped answers one match list per group" );

    std::vector<std::size_t> perTag( specs.size(), 0 );
    const flipimpact::SymbolLineIndex lines = flipimpact::buildSymbolLineIndex( ing );
    std::vector<char> isSeed( ing.symbols.size(), 0 );
    for( const NodeId s : seeds )
    {
        if( s < isSeed.size() ) { isSeed[s] = 1; }
    }
    // Each hit's spec, or specs.size() when its language has no row naming that pattern (it compiled in another grammar).
    std::vector<std::size_t> specOf( got[0].size(), specs.size() );
    std::vector<const AstMatch*> shadows;   // type-parameter scopes (and their @t names), in walk order
    for( std::size_t h = 0; h < got[0].size(); ++h )
    {
        const AstMatch& m = got[0][h];
        const std::size_t i = std::size_t( std::find_if( specs.begin(), specs.end(), [ & ]( const AstQuerySpec& sp ) { return sp.tag == m.tag; } ) - specs.begin() );
        ASSUME( i < specs.size(), "every hit carries the tag of a spec this call built" );
        ++perTag[i];
        const std::uint64_t langBit = m.fileId < ing.files.size() ? std::uint64_t( 1 ) << static_cast<unsigned>( langOfPath( ing.files[m.fileId] ) ) : 0;
        if( ( specLangs[i] & langBit ) != 0 )
        {
            specOf[h] = i;
            if( specRole[i] == SpecRole::Shadow ) { shadows.push_back( &m ); }
        }
    }
    // Sorted by ( file, start ) so a hit reads only its own file's shadows that open at or before it — the scan was every
    // shadow in the corpus per hit, O( hits x shadows ) with both up to the match budget. The containment test is unchanged
    // and a hit is shadowed by ANY container, so the order inside a run of equal starts cannot change the answer.
    std::sort( shadows.begin(), shadows.end(), []( const AstMatch* a, const AstMatch* b )
               { return a->fileId != b->fileId ? a->fileId < b->fileId : a->startByte < b->startByte; } );
    const auto shadowed = [ & ]( const AstMatch& m )
    {
        auto it = std::lower_bound( shadows.begin(), shadows.end(), m.fileId, []( const AstMatch* sc, std::uint32_t f ) { return sc->fileId < f; } );
        for( ; it != shadows.end() && ( *it )->fileId == m.fileId && ( *it )->startByte <= m.startByte; ++it )
        {
            if( m.endByte <= ( *it )->endByte )
            {
                return true;
            }
        }
        return false;
    };
    for( std::size_t h = 0; h < got[0].size(); ++h )
    {
        const AstMatch& m = got[0][h];
        if( specOf[h] == specs.size() || specRole[specOf[h]] == SpecRole::Shadow || shadowed( m ) )
        {
            continue;   // another grammar's compile, a shadow row itself, a same-named type PARAMETER or a std-path name
        }
        if( specRole[specOf[h]] == SpecRole::Block )
        {
            // Every definition inside the block is a user (the @t / @p captures are a name and a path: none fits there).
            // A linear pass over the file's definitions per block hit: a file holds few impl blocks naming one type.
            if( m.fileId < lines.byFile.size() )
            {
                for( const NodeId id : lines.byFile[m.fileId] )
                {
                    const Symbol& sym = ing.symbols[id];
                    if( !isSeed[id] && sym.sigStartByte >= m.startByte && sym.endByte <= m.endByte && sym.sigStartByte < sym.endByte )
                    {
                        tier.users.push_back( id );
                    }
                }
            }
            continue;
        }
        const NodeId host = flipimpact::innermostAtLine( ing, lines, m.fileId, m.line );
        if( host == kNoNode )
        {
            tier.scopeFiles.push_back( m.fileId );
        }
        else if( !isSeed[host] )
        {
            tier.users.push_back( host );
        }
    }
    tier.sitesCapped = std::any_of( perTag.begin(), perTag.end(), []( std::size_t n ) { return n >= kTypeMentionMatchBudget; } );
    rw::sortutil::sortUnique( tier.users );
    rw::sortutil::sortUnique( tier.scopeFiles );
    std::erase_if( tier.scopeFiles, [ & ]( std::uint32_t f ) { return std::binary_search( tier.defFiles.begin(), tier.defFiles.end(), f ); } );
    ENSURES( std::is_sorted( tier.users.begin(), tier.users.end() ), "users ascend (the reach merge below relies on it)" );
    return tier;
}

// The --impact walk with the type tier folded in. Unarmed: exactly the call walk (transitiveCallersDepth +
// provenCallerReach over the seeds), so a function impact is byte-identical. Armed: every type user enters the walk at
// d=1 beside SYM's direct callers, their callers follow; `proven` counts a type user as proven (the parser read the
// mention — it is not a name-only CALL edge), and `typeOnly` marks the nodes the plain call walk does not reach.
struct ImpactReach
{
    std::vector<NodeId>        reach;      // ascending, seeds excluded
    std::vector<std::uint32_t> depth;      // per node
    std::vector<char>          proven;     // provenCallerReach's shape (empty when the graph has no name-only flags)
    std::vector<char>          typeOnly;   // per node; empty when the tier is unarmed
};

inline ImpactReach impactReachWithTypes( const Graph& g, std::span<const NodeId> seeds, const TypeUseTier& tier )
{
    ImpactReach r;
    if( !tier.armed )
    {
        r.reach  = transitiveCallersDepth( g, seeds, &r.depth );
        r.proven = provenCallerReach( g, seeds );
        return r;
    }
    r.reach = transitiveCallersDepth( g, seeds, &r.depth, tier.users );
    std::vector<NodeId> both( seeds.begin(), seeds.end() );
    both.insert( both.end(), tier.users.begin(), tier.users.end() );
    r.proven = provenCallerReach( g, both );
    const std::vector<NodeId> byCalls = transitiveCallers( g, seeds );
    r.typeOnly.assign( r.depth.size(), 0 );
    for( const NodeId n : r.reach )
    {
        r.typeOnly[n] = std::binary_search( byCalls.begin(), byCalls.end(), n ) ? 0 : 1;
    }
    return r;
}

// The rollup's view of the tier (graph.h ImpactFileRollup), or null when the tier is unarmed — `out` is the caller's storage
// and must outlive the rollup call; its spans borrow `tier`, its typeOnly `walk`.
inline const ImpactTypeFold* impactTypeFold( const TypeUseTier& tier, const ImpactReach& walk, ImpactTypeFold& out )
{
    if( !tier.armed )
    {
        return nullptr;
    }
    out = ImpactTypeFold{ tier.defFiles, tier.scopeFiles, &walk.typeOnly, tier.users.size(), tier.typeDefs, tier.sitesCapped };
    return &out;
}

} // namespace rw
