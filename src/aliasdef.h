#pragma once
// aliasdef.h — INDEX-ALIAS-CONST: the ONE reader of "this declaration is another name for that target".
//
// A C++ `using X = Y;` / `namespace L = lib;` / function-type or pointer typedef becomes a definition whose TARGET is
// the written text the parser hands back. Every site that needs the alias's target reads it here: the tags pass
// (ingest_sidecap.h captureTagsFacts: which captures to keep, and where the target starts — model.h AliasTarget, one
// 8-byte row per alias def), and the printer that shows it (--defs to=, defslookup.h aliasTargetText). The three older
// C/C++ alias readers (ingest_binds.h fnPtrAliasName, ingest_relations.h aliasSpecifierAndName, ingest_sidecap.h's
// typedef-name mention filter) keep their own walks for now; aliasShapeOf is the shape they can adopt
// (reports/index-alias-const.md, adoption plan).
//
// LANGUAGE LAYER (explicit, one arm per language): C++ reads node kinds the grammar fixes (alias_declaration's `type`
// field, namespace_alias_definition's last named non-comment child, type_definition's `type` field). Every other language returns
// None today. A TypeScript arm (module-level `const X = <alias- or table-shaped value>` against an allowlist of
// right-hand-side shapes) was measured and carded (TS-CONST-DEFS): the defs verb found the tables, the task-phrased
// answers did not print them. It returns as one more arm here, with its own AliasForm values.

#include "infra/fieldid.h"
#include "infra/nodekind.h"
#include "infra/tschildren.h"
#include "model.h"

#include <tree_sitter/api.h>

#include <cstdint>

namespace rw
{

enum class AliasForm : std::uint8_t
{
    None,            // not an alias
    TypeAlias,       // C++ `using X = Y;` and its template / class-scope forms, a function-type or pointer typedef
    NamespaceAlias,  // C++ `namespace L = lib;`
};

struct AliasShape
{
    AliasForm form   = AliasForm::None;
    TSNode    target {};   // the written target; null when form == None
};

// The shape of the declaration node a definition capture's role node names.
inline AliasShape aliasShapeOf( Lang lang, TSNode decl )   // not noexcept: the child cursor allocates (infra/tschildren.h)
{
    if( ts_node_is_null( decl ) )
    {
        return {};
    }
    const char* t = ts_node_type( decl );
    switch( lang )
    {
    case Lang::Cpp:
        if( kindIs( t, "alias_declaration" ) || kindIs( t, "type_definition" ) )
        {
            const TSNode ty = fieldChild( decl, NodeField::Type );
            return ts_node_is_null( ty ) ? AliasShape{} : AliasShape{ AliasForm::TypeAlias, ty };
        }
        if( kindIs( t, "namespace_alias_definition" ) )
        {
            // the last named child that is no comment: `namespace L = lib /* c */;` names lib, never the comment (a comment is a
            // named extra); one cursor walk (infra/tschildren.h: an indexed walk is quadratic under a comment flood)
            TSNode      target {};
            ChildCursor cursor( decl );
            forEachNamedChild( decl, cursor.cur, [ & ]( TSNode c )
                               {
                                   if( !kindIs( ts_node_type( c ), "comment" ) )
                                   {
                                       target = c;
                                   }
                                   return true;
                               } );
            return ts_node_is_null( target ) ? AliasShape{} : AliasShape{ AliasForm::NamespaceAlias, target };
        }
        return {};
    default:
        return {};   // every other language: no arm yet (TS-CONST-DEFS is the carded TypeScript one)
    }
}

}   // namespace rw
