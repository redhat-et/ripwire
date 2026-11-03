#pragma once
// memberowner.h — QUALNAME-1: a member symbol row names its owner, n="Owner.name", from the STORED scope.
//
// A bare member name made the reader re-resolve it: a --callers list of `run`, `run`, `run` (three owners) or a <d n="render"
// sc="CmdRenderer"> row that a reader (or a grader) has to recombine. The owner is read off the parser's own scope (Symbol::scope,
// the sc= every other surface prints), never off the name, and printed only when the index DEFINES the scope's last segment as a
// member owner in the row's language — a class, struct, interface or named type, or a module (`@definition.module` is
// SymKind::Other: Rust `mod`, Ruby `module`, Elixir `defmodule`). A printed scope is a claim, so it is exact or bare:
//   * no stored scope (Java, C#, Swift, Kotlin `object` today) → bare: a floor, not a claim;
//   * a TS/JS METHOD (no stored scope: langfacts.h containmentOwners) → the ONE class whose body holds it, read by graph.h
//     containedOwnersOf — the rule the written-spelling tier binds `Class.method` by, so the printed name resolves back
//     (lane js-def-naming: nunjucks' two environment.js `render`s print Environment.render and Template.render). Bare when a
//     function or method holds it (a local def), when no class does (an object-literal member), and when two classes nest
//     around it (a floor: one owner prints, never a guessed chain);
//   * a type or module row → bare (a class carries its own name as sc=; never `Box.Box`);
//   * a C++ namespace scope → bare (a namespace is no indexed definition, so a namespace-scope function stays a free function) —
//     unless a class of the same name is defined in that language: the owner test is name-keyed, so `namespace Logger { int init(); }`
//     beside `class Logger` prints `Logger::init`, the valid qualified name of a function that is not a member;
//   * an EXTENT-SUSPECT symbol → bare: a recovered parse can file a free function under the struct that swallowed it (extentsuspect.h);
//   * a FUNCTION-LOCAL def (Symbol::fnLocal: a Python/JS closure, whose scope walk skips the enclosing method) → bare: its owner
//     would read `Class.fn` for a function no `Class` instance carries.
// The spelling is the full stored scope, the language's member separator (langfacts.h memberSeparator: `::` C/C++/Rust (PHP methods store no scope, so none prints), `#`
// Ruby, `.` elsewhere), then the name — every spelling a selector resolves. A constructor is a member by the same rule and prints
// in its language's own form (`Route.__init__`, `NinjaMain::NinjaMain`, `Config::new`).
// ONE rule for every row kind that prints a member: --path hops (defattrib.h emitPathHopRows), the --callers/--callees and --impact
// rows, the <d> signature rows (serialize.h sigRowHead, where it FOLDS sc= into n=). Built once per answer: one pass collecting the
// (language, name) of every owner definition, then a binary search per row.

#include "graph.h"       // namespaceCompatible — the one statement of "a type definition"
#include "langfacts.h"   // memberSeparator — the per-language spelling, as a column
#include "model.h"
#include "graphlegend.h"   // memberOwnerLegend / memberOwnerContainedLegend — memberOwnerLegendFor's two clauses
#include "infra/sortutil.h"   // svLess: the explicit byte order a std::sort over string_view needs

#include <algorithm>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The kinds a scope must be defined as to print as an owner — and the kinds of a row that is itself an owner (never qualified).
// Reuse-first: the type half is graph.h namespaceCompatible's Type rule, plus a module (SymKind::Other). (Train 30's PATH-OWNERS
// rule, moved here from defattrib.h so the serialize.h rows can reach it.)
inline bool isMemberOwnerKind( SymKind k ) noexcept
{
    return k == SymKind::Other || namespaceCompatible( RefRole::Type, k );
}
// scopeLastSegment (the segment the index must define as an owner) lives in model.h, beside Symbol::scope: testmap.h's
// class-new owner reads it too (train 33: IX-5 and QUALNAME-1 each moved the same helper out of defattrib.h).

// The containment languages' symbols per file, ascending start (id breaks a tie): what containedOwnersOf scans for a member's class.
inline SymbolsByFile containmentSymbolsByFile( const IngestResult& ing )
{
    return symbolsByFile(
        ing, []( const Symbol& t ) { return langFacts( t.lang ).containmentOwners; },
        [ &ing ]( NodeId a, NodeId b )
        {
            const Symbol& x = ing.symbols[ a ];
            const Symbol& y = ing.symbols[ b ];
            return x.sigStartByte != y.sigStartByte ? x.sigStartByte < y.sigStartByte : a < b;
        } );
}

class MemberOwners
{
public:
    // One pass over the symbols: the (language, name) of every member-owner definition, sorted for the per-row lookup.
    explicit MemberOwners( const IngestResult& ing ) : ing_( ing )
    {
        for( const Symbol& t : ing.symbols )
        {
            if( isMemberOwnerKind( t.kind ) && !t.name.empty() )
            {
                defined_.emplace_back( t.lang, std::string_view( t.name ) );
            }
        }
        std::sort( defined_.begin(), defined_.end(), keyLess );
        defined_.erase( std::unique( defined_.begin(), defined_.end() ), defined_.end() );
    }
    // The owner a member row prints ("" = bare): the symbol's full stored scope, when the rule above holds. An extent-suspect symbol's
    // scope was inferred from a recovered parse (extentsuspect.h), so it is no claim: bare.
    std::string_view ownerOf( const Symbol& s ) const
    {
        if( isMemberOwnerKind( s.kind ) || s.fnLocal || s.extentSuspect != 0 )
        {
            return {};
        }
        if( s.scope.empty() )
        {
            return containedOwnerOf( s );
        }
        const std::string_view last = scopeLastSegment( s.scope );
        return !last.empty() && std::binary_search( defined_.begin(), defined_.end(), Key{ s.lang, last }, keyLess )
                   ? std::string_view( s.scope )
                   : std::string_view();
    }

private:
    // A TS/JS method's owner by containment (see the header): the one enclosing class, else "". The per-file buckets of the
    // containment languages' symbols (ascending start) are built at the first such row, so an answer with none pays nothing.
    std::string_view containedOwnerOf( const Symbol& s ) const;   // defined below the class

    using Key = std::pair<Lang, std::string_view>;
    static bool keyLess( const Key& a, const Key& b ) noexcept
    {
        if( a.first != b.first )
        {
            return a.first < b.first;   // language first: an owner counts only in the row's own language
        }
        return sortutil::svLess( a.second, b.second );
    }
    const IngestResult&                   ing_;
    std::vector<Key>                      defined_;
    mutable std::optional<SymbolsByFile>  byFile_;
};

inline std::string_view MemberOwners::containedOwnerOf( const Symbol& s ) const
{
    if( s.kind != SymKind::Method || !langFacts( s.lang ).containmentOwners )
    {
        return {};
    }
    if( !byFile_ )
    {
        byFile_.emplace( containmentSymbolsByFile( ing_ ) );
    }
    if( s.fileId >= byFile_->size() )
    {
        return {};
    }
    const FileSymbols&    bucket = ( *byFile_ )[ s.fileId ];
    const ContainedOwners c      = containedOwnersOf( ing_, std::span<const NodeId>( bucket.data(), bucket.size() ), s );
    return !c.nested && c.chain.size() == 1 ? c.chain.front() : std::string_view();
}

// Whether `s` could print an owner at all: a stored scope, or a TS/JS method (containment). The cheap pre-test the answer-level
// "does any row print an owner" checks run before they pay for a MemberOwners pass.
inline bool memberOwnerPossible( const Symbol& s ) noexcept
{
    return !s.scope.empty() || ( s.kind == SymKind::Method && langFacts( s.lang ).containmentOwners );
}

// Which owner clauses `rows` need: any row printing an owner, and any whose owner was read by containment (TS/JS). The owner
// pass runs only when some row could print one at all.
struct MemberOwnerRows
{
    bool any       = false;
    bool contained = false;
};
inline MemberOwnerRows memberOwnerRows( const IngestResult& ing, std::span<const NodeId> rows )
{
    MemberOwnerRows out;
    if( std::none_of( rows.begin(), rows.end(), [ & ]( NodeId id ) { return memberOwnerPossible( ing.symbols[ id ] ); } ) )
    {
        return out;
    }
    const MemberOwners owners( ing );
    for( const NodeId id : rows )
    {
        const Symbol& s = ing.symbols[ id ];
        if( !owners.ownerOf( s ).empty() )
        {
            out.any       = true;
            out.contained = out.contained || s.scope.empty();
        }
    }
    return out;
}
// Both owner clauses for `rows` (graphlegend.h): the shared one when any row prints an owner, the TS/JS one when a containment
// owner is among them.
inline std::string memberOwnerLegendFor( MemberOwnerRows r )
{
    return std::string( memberOwnerLegend( r.any ) ) + memberOwnerContainedLegend( r.contained );
}

// The separator between an owner and a member name in `l` (langfacts.h).
inline std::string_view memberSeparator( Lang l ) noexcept
{
    return langFacts( l ).memberSeparator;
}
// The name a member row prints, unescaped: "Owner<sep>name" when `owner` is set, else the bare name.
inline std::string qualifiedMemberName( std::string_view owner, const Symbol& s )
{
    if( owner.empty() )
    {
        return s.name;
    }
    const std::string_view sep = memberSeparator( s.lang );
    std::string            q;
    q.reserve( owner.size() + sep.size() + s.name.size() );
    q.append( owner ).append( sep ).append( s.name );
    return q;
}
inline std::string qualifiedMemberName( const MemberOwners& owners, const Symbol& s )
{
    return qualifiedMemberName( owners.ownerOf( s ), s );
}

}   // namespace rw
