#pragma once

// countfloor.h — when a per-row count is a FLOOR, and which call finds the rest.
//
// WHY. A root's counts_floor="1" and a verb legend's "a zero means none found" are blanket statements; the reader
// meets them once, far from the number. A graded comparison showed what that costs: of the false claims scored
// against this tool, eight were a ZERO or "none" read as a TOTAL — a method's `<enc callers="0">` while six calls the
// resolver declined to bind could have meant it, a module variable's `<enc callers="0">` while another file READS it
// (it is never called), a C struct's `--safe-delete` answering callers/uses="0" risk="none-found" although its type
// mentions — which the index does not capture at all — sat in thirty files. Each number was what the graph
// held; none of them was the answer the reader took from it.
//
// THE RULE. A row's count stays a plain total only when nothing this index knows could add to it. It is a floor —
// spelled `<count>_floor="1"` beside the number (the locals="N" locals_floor="1" precedent), with a pasteable
// follow-up that finds the rest — when the index itself holds EVIDENCE of a miss for THAT definition:
//   * declined  — a call the resolver refused to bind named it among its candidates (graph.h declinedCallsNaming);
//   * unbound   — a call or macro site SPELLED like it bound to no definition of that name at all (a receiver the
//                 resolver could not type, a name whose every candidate was filtered), from a symbol that is not
//                 already one of its callers;
//   * value     — the function is stored or passed as a value (valuerefindex.h), so it is called by another name;
//   * unmodelled — its KIND is used by reading or naming it (a variable, a struct, an interface, a field), and a
//                 call count cannot see a read or a type mention at all.
// None of these says the missing callers EXIST: an unbound `x.last()` may be a list's own method. The marker is a
// statement about what was NOT read, which is exactly what a total would have claimed was read.
//
// CLI AND MCP. Every input here is identical in the lean (CLI nav verbs) and rich (MCP) ingest families: call and
// macro references, inherit references, the graph's edges and declines, value references (both families capture
// them, ingest_sidecap.h) and symbol kinds. Read/write/type references — the rich family's extra rows — are never
// consulted, so the two surfaces cannot disagree about a floor.

#include "graph.h"           // Graph, declinedCallsNaming — the declined evidence and the in-edge CSR
#include "model.h"
#include "nextverb.h"        // nextFlag — the follow-up's shell-safe spelling
#include "valuerefindex.h"   // ValueRefIndex, valueRefCallerRows — the value evidence
#include "infra/Diagnostics.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// How a definition is USED, for the one question a caller count can answer.
//   Calls    — a call reaches it: functions, methods, function-like macros.
//   NotCalls — it is read or named more than it is called: a variable, a class or struct (a constructor call is one use, a
//              type mention, a base clause or an isinstance are the others), an interface, a field, anything unclassified.
//              callers= is structurally blind to most of its uses.
//   NotCode  — a markdown heading or a file's module scope: no code calls or reads it, so a zero there is simply true.
enum class UseForm : std::uint8_t { Calls, NotCalls, NotCode };

// One reading per SymKind, in enum order (model.h's kRefRoleTagTable shape: a declarative table, and the static_assert
// is the guard a -Werror=switch would be — a NEW kind without a reading is a build error, never a silent default).
inline constexpr UseForm kUseFormOfKind[] = {
    UseForm::Calls,      // Function
    UseForm::Calls,      // Method
    UseForm::NotCalls,   // Class: a constructor call is one use; a type mention, a base clause, an isinstance are the rest
    UseForm::NotCalls,   // Struct
    UseForm::NotCalls,   // Interface
    UseForm::NotCalls,   // Var
    UseForm::NotCode,    // Section (a markdown heading)
    UseForm::Calls,      // Macro (a function-like invocation binds as a call)
    UseForm::NotCalls,   // Field
    UseForm::NotCalls,   // Other
    UseForm::NotCode,    // ModuleScope
    UseForm::NotCalls,   // NamedType (Go `type N string`): a conversion `N( s )` is one use; a type mention is the rest, as Struct
    UseForm::NotCalls,   // Alias (Go `type A = B`): read by naming it, as Struct
    UseForm::NotCalls,   // FuncType (Go `type F func(...)`): a conversion `F( fn )` is one use; parameter/field types are the rest
};
static_assert( std::size( kUseFormOfKind ) == kSymKindCount, "kUseFormOfKind: one reading per SymKind, in enum order" );

inline UseForm useFormOf( const Symbol& s ) noexcept
{
    return enumTableAt( kUseFormOfKind, s.kind, UseForm::NotCalls );   // past the enum: the conservative reading (a floor)
}

// The languages whose read/write/type uses reach the use-site table in an ingest that captured value uses
// (ingest_sidecap.h arms that pass for C++, ObjC and Python only). Outside them `--uses` lists calls and value references
// but never a read, so the honest follow-up for a NotCalls symbol is the literal scan.
inline constexpr std::array<bool, kLangCount> kValueUsesArmed = []
{
    std::array<bool, kLangCount> armed {};   // value-initialised: every language unarmed unless listed below
    armed[ static_cast<std::size_t>( Lang::Cpp ) ]    = true;
    armed[ static_cast<std::size_t>( Lang::ObjC ) ]   = true;
    armed[ static_cast<std::size_t>( Lang::Python ) ] = true;
    return armed;
}();

inline bool valueUsesArmedFor( Lang lang ) noexcept
{
    return enumTableAt( kValueUsesArmed, lang, false );
}

// The follow-up that finds what a floored count could not: the uses verb lists every call, value and (where armed)
// read site spelled like the name, bound or not; a NotCalls symbol in a language whose reads are never captured gets
// the literal scan instead, which is the only verb that can see `struct cell c;`.
//
// A `.h` definition is the exception: the grammar reads it as C++, but its users are as often `.c` files, whose reads the
// uses verb never sees — so a header's NotCalls symbol gets the literal scan too (`struct cell` in a.h used in a.c).
inline std::string countFloorNext( const IngestResult& ing, const Symbol& s )
{
    const std::string_view path    = s.fileId < ing.files.size() ? std::string_view( ing.files[ s.fileId ] ) : std::string_view();
    const bool             literal = useFormOf( s ) == UseForm::NotCalls && ( !valueUsesArmedFor( s.lang ) || path.ends_with( ".h" ) );
    return nextFlag( literal ? "--grep=" : "--uses=", s.name );
}

// One row's verdict. `next` is a CLI flag spelling (MCP prints the same text), empty exactly when !isFloor.
struct CallerFloor
{
    bool        isFloor = false;
    std::string next;
};

namespace countfloor
{

// Row indices by the NAME their definitions share — a name may head several rows (two <enc> chains `A::f` and `B::f`),
// and the reference table is keyed by spelling, so every lookup below asks of the name.
using RowsOfName = HashMap<std::string_view, std::vector<std::uint32_t>>;
using IdsOfName  = HashMap<std::string_view, std::vector<NodeId>>;

// The use form of a row: NotCalls if ANY definition is read/named (its count is blind to that one), else Calls if any is
// called, else NotCode (headings and module scopes only).
inline UseForm rowUseForm( const IngestResult& ing, std::span<const NodeId> ids ) noexcept
{
    bool anyCalls = false;
    for( const NodeId id : ids )
    {
        const UseForm form = id < ing.symbols.size() ? useFormOf( ing.symbols[id] ) : UseForm::NotCode;
        if( form == UseForm::NotCalls )
        {
            return UseForm::NotCalls;
        }
        anyCalls = anyCalls || form == UseForm::Calls;
    }
    return anyCalls ? UseForm::Calls : UseForm::NotCode;
}

// For every symbol whose name heads a row, `relatedOf( id )` appended under that name, then sorted and deduplicated so a
// membership test is a binary search: the callers of every same-named definition, or every implementor of one.
template<class RelatedOf>
inline IdsOfName relatedByName( const IngestResult& ing, const RowsOfName& rowsOfName, std::size_t idLimit, RelatedOf&& relatedOf )
{
    IdsOfName out;
    for( NodeId id = 0; id < ing.symbols.size() && id < idLimit; ++id )
    {
        const auto it = rowsOfName.find( std::string_view( ing.symbols[id].name ) );
        if( it != rowsOfName.end() )
        {
            relatedOf( id, out[ it->first ] );
        }
    }
    for( auto& [ name, ids ] : out )
    {
        std::sort( ids.begin(), ids.end() );
        ids.erase( std::unique( ids.begin(), ids.end() ), ids.end() );
    }
    return out;
}

// ONE pass over the reference table: a reference `isKind` accepts, spelled like a row's name, from a symbol that is not
// in that name's `bound` set (or from file scope), marks every row of the name. `isBound( r, ids )` decides whether the
// reference is accounted for by that name's sorted `bound` ids (empty when the name has none); `mark( row )` is the verdict.
template<class IsKind, class IsBound, class Mark>
inline void markUnboundSpellings( const IngestResult& ing, const RowsOfName& rowsOfName, const IdsOfName& bound, IsKind&& isKind,
                                  IsBound&& isBound, Mark&& mark )
{
    for( const Reference& r : ing.references )
    {
        if( !isKind( r ) )
        {
            continue;
        }
        const auto it = rowsOfName.find( std::string_view( r.calleeName ) );
        if( it == rowsOfName.end() )
        {
            continue;
        }
        const auto                    boundIt = bound.find( it->first );
        const std::span<const NodeId> ids     = boundIt != bound.end() ? std::span<const NodeId>( boundIt->second ) : std::span<const NodeId>();
        if( !isBound( r, ids ) )
        {
            for( const std::uint32_t row : it->second )
            {
                mark( row );
            }
        }
    }
}

// The plain bound test: the reference's own enclosing symbol is one of the name's bound ids (sorted).
inline bool fromIsBound( const Reference& r, std::span<const NodeId> ids ) noexcept
{
    return r.fromSymbol != kNoNode && std::binary_search( ids.begin(), ids.end(), r.fromSymbol );
}

// An inherit clause is bound when the graph listed its DERIVED type as an implementor. graph.h's inheritance pass names
// that type two ways besides the enclosing symbol, and this must read it the same way or a bound clause reads as a miss:
// a Rust `impl Trait for T` header lies outside T's span, so T's NAME rides in `qualifier` (empty for every other
// language's inherit ref); and a reopened Ruby class is listed once, under its canonical opening, so the clause in
// another opening comes from a symbol id the list does not hold but a symbol NAME it does. By name, like every floor
// here: a same-named derived type elsewhere that the graph bound answers for this clause too ("may", not "does").
inline bool inheritIsBound( const IngestResult& ing, const Reference& r, std::span<const NodeId> ids ) noexcept
{
    if( fromIsBound( r, ids ) )
    {
        return true;
    }
    const std::string_view derived = r.isInherit && !r.qualifier.empty()                           ? std::string_view( r.qualifier )
                                     : r.fromSymbol != kNoNode && r.fromSymbol < ing.symbols.size() ? std::string_view( ing.symbols[ r.fromSymbol ].name )
                                                                                                    : std::string_view();
    return !derived.empty()
           && std::ranges::any_of( ids, [ & ]( NodeId id ) { return id < ing.symbols.size() && ing.symbols[id].name == derived; } );
}

inline bool isCallSpelling( const Reference& r ) noexcept
{
    return ( r.role == RefRole::Call || r.role == RefRole::Macro ) && !r.isInherit && !r.isDocLink && !r.isCompose && r.lang != Lang::Markdown;
}

// The value evidence for one row: a non-decorator value reference (a decorator row, into="@name", is a fact about the
// definition, not a path that calls it).
inline bool hasValueUse( const IngestResult& ing, const ValueRefIndex& vri, std::span<const NodeId> ids )
{
    for( const ValueRefRow& vr : valueRefCallerRows( ing, vri, ids ).rows )
    {
        if( vr.ref < ing.references.size() && !ing.references[ vr.ref ].fieldName.starts_with( '@' ) )
        {
            return true;
        }
    }
    return false;
}

}   // namespace countfloor

// callers= floors for a batch of rows: sets[i] is one row's definitions (all one NAME — a grep <enc> row's ids, a
// safe-delete selector's defs). ONE pass over the symbols and ONE over the references, whatever the row count —
// never a per-row rescan of the reference table (editcheck.h's rule). `vri` may be null: then it is built here, once,
// and only when a Calls row is still undecided after the cheaper evidence. Evidence, cheapest first: the use form, the
// declined calls, the unbound same-name calls, the value uses.
inline std::vector<CallerFloor> callerFloors( const IngestResult& ing, const Graph& g, std::span<const std::vector<NodeId>> sets,
                                              const ValueRefIndex* vri = nullptr )
{
    std::vector<CallerFloor> out( sets.size() );
    countfloor::RowsOfName   rowsOfName;
    std::vector<std::uint32_t> pending;   // Calls rows the use form and the declines left undecided
    for( std::uint32_t i = 0; i < sets.size(); ++i )
    {
        const std::vector<NodeId>& ids = sets[i];
        if( ids.empty() || ids[0] >= ing.symbols.size() )
        {
            continue;
        }
        const UseForm form = countfloor::rowUseForm( ing, ids );
        out[i].isFloor = form == UseForm::NotCalls || ( form == UseForm::Calls && declinedCallsNaming( g, ids ) > 0 );
        if( form == UseForm::Calls && !out[i].isFloor )
        {
            rowsOfName[ std::string_view( ing.symbols[ ids[0] ].name ) ].push_back( i );
            pending.push_back( i );
        }
    }

    if( !pending.empty() )
    {
        // A call from a symbol with an edge into ANY definition of the name was bound somewhere — to this row or to a
        // same-named sibling — so it is not evidence of a miss. Nor is a call from a definition of the name ITSELF: the
        // graph drops self-loops (CallDisposition::Self), so recursion commits no edge, yet the call bound to this very
        // definition. By name, like the rest: a definition calling a same-named function elsewhere is read as recursion.
        const auto* inRo = g.inEdges.rowOffsets();
        const auto* inCi = g.inEdges.colIndices();
        const countfloor::IdsOfName boundCallers = countfloor::relatedByName( ing, rowsOfName, g.wOutDeg.size(),
            [ & ]( NodeId id, std::vector<NodeId>& into )
            {
                into.push_back( id );
                into.insert( into.end(), inCi + inRo[id], inCi + inRo[id + 1] );
            } );
        countfloor::markUnboundSpellings( ing, rowsOfName, boundCallers, countfloor::isCallSpelling, countfloor::fromIsBound,
                                          [ & ]( std::uint32_t row ) { out[row].isFloor = true; } );

        std::optional<ValueRefIndex> own;   // one more pass over the table: built only if a row is still open
        for( const std::uint32_t row : pending )
        {
            if( out[row].isFloor )
            {
                continue;
            }
            if( vri == nullptr && !own )
            {
                own.emplace( ing );
            }
            out[row].isFloor = countfloor::hasValueUse( ing, vri != nullptr ? *vri : *own, sets[row] );
        }
    }

    for( std::uint32_t i = 0; i < sets.size(); ++i )
    {
        if( out[i].isFloor )
        {
            out[i].next = countFloorNext( ing, ing.symbols[ sets[i][0] ] );
        }
    }
    return out;
}

// implementors= floors for the <lego> rows: an inherit reference spelled like the interface's name from a type that
// is in NO implementor list of any definition of that name — an `extends`/`implements` clause the graph did not
// bind (a cross-language filter, a qualified base it could not place). ONE pass over the references for the batch.
// The structural-typing limit (a TS class or Go type that satisfies an interface without naming it) leaves no
// reference at all, and is stated in the legend rather than guessed at here.
inline std::vector<char> implementorFloors( const IngestResult& ing, const std::vector<std::vector<NodeId>>& graphImplementors,
                                            std::span<const NodeId> ifaces )
{
    std::vector<char>      out( ifaces.size(), 0 );
    countfloor::RowsOfName rowsOfName;
    for( std::uint32_t i = 0; i < ifaces.size(); ++i )
    {
        if( ifaces[i] < ing.symbols.size() )
        {
            rowsOfName[ std::string_view( ing.symbols[ ifaces[i] ].name ) ].push_back( i );
        }
    }
    if( rowsOfName.empty() )
    {
        return out;
    }
    const countfloor::IdsOfName boundDerived = countfloor::relatedByName( ing, rowsOfName, graphImplementors.size(),
        [ & ]( NodeId id, std::vector<NodeId>& into ) { into.insert( into.end(), graphImplementors[id].begin(), graphImplementors[id].end() ); } );
    countfloor::markUnboundSpellings( ing, rowsOfName, boundDerived, []( const Reference& r ) { return r.isInherit || r.role == RefRole::Extends; },
                                      [ & ]( const Reference& r, std::span<const NodeId> ids ) { return countfloor::inheritIsBound( ing, r, ids ); },
                                      [ & ]( std::uint32_t row ) { out[row] = 1; } );
    return out;
}

// The targeted lego verb's clause for implementors_floor=/floor_next=, emitted as its own comment exactly when the root's
// interface carries them (kLegoLegend is one closed literal — the graphUnindexedLegendComment route). CLI and MCP share it.
inline constexpr const char* kImplementorsFloorLegendComment =
    "<!-- ripwire lego: implementors_floor=\"1\": an extends/implements clause spelled like this interface bound to NO definition "
    "(a cross-language base, a qualified base the graph could not place), so implementors= may be short by it; it does NOT mean "
    "another implementor exists. floor_next= lists every extends site of the name, bound or not. A type that satisfies an "
    "interface without naming it (structural typing) leaves no clause at all and is never counted. -->";

// lane lego-transitive: the full dialect's clause for the deeper implementor rows, emitted as its own comment exactly when the
// targeted interface HAS a depth >= 2 implementor (the kImplementorsFloorLegendComment route above). No double hyphen inside:
// it rides an XML comment. CLI and MCP share it.
inline constexpr const char* kLegoClosureLegendComment =
    "<!-- ripwire lego: transitive=N counts the implementors BELOW a direct one (depth 2 and deeper), each listed once at its "
    "shallowest depth as <impl via= depth=>: via= names the type it extends that reached it, depth= its hops below this "
    "interface; a direct row carries neither, and implementors= still counts the direct rows alone. The deeper rows are one page: "
    "transitive_shown= rows printed when it is cut, transitive_offset= the first one shown, has_more=\"1\" and "
    "next= the call for the next page. -->";

inline const char* legoClosureLegendComment( const std::vector<std::vector<NodeId>>& graphImplementors, NodeId focus )
{
    for( const ImplementorRow& row : implementorClosure( graphImplementors, focus ) )
    {
        if( row.depth >= 2 )
        {
            return kLegoClosureLegendComment;
        }
    }
    return "";
}

inline const char* implementorsFloorLegendComment( const IngestResult& ing, const std::vector<std::vector<NodeId>>& graphImplementors, NodeId focus )
{
    const NodeId one[1] = { focus };
    return implementorFloors( ing, graphImplementors, std::span<const NodeId>( one ) )[0] ? kImplementorsFloorLegendComment : "";
}

}   // namespace rw
