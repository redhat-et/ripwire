#pragma once
// forslots.h — INITIALIZER SLOTS on the shown table rows of a compact-route --for answer (lane peer-s, card FOR-SLOTS).
//
// WHY. A compact --for answer (bodies="0") names a struct/table initializer as one <d> row: its declaration line
// (`const struct window_mode window_copy_mode =`), never the functions it holds. A question whose answer is one of those
// functions (tmux's copy mode: `.command = window_copy_command`) then had the table on screen and the function nowhere, though
// the index already binds it (`--callers=window_copy_command` prints the `<vr … into="window_copy_mode.command">` row).
// Mechanism learned from codegraph's handleExplore (MIT; a constant initializer is a seedable node whose span shows the
// `.field = fn` lines) — no code taken.
//
// WHAT. On a SHOWN row whose symbol is neither a callable nor a class/struct/interface (a variable, a constant: an initializer)
// and that holds at least one function value by the index, the row gains
//   slots="k=fn,…"   up to kForSlotCap pairs, in source order: k = the slot as the --callers/--callees `into=` spells it, less the
//                    row's own name (`.command` → `command`; a positional C entry stays `[0]`; a Python key stays `["run"]`),
//                    fn = the function the index binds there (one pair per distinct target of a by-name lookup), and
//   slots_more="N"   N more pairs it did not list (absent when none was cut).
// A pair is a Value reference (RefRole::Value, src/valuerefindex.h) made INSIDE the row's symbol and resolved to a function:
// binding, never a call, never "relevant". A key or a name a comma or `=` would split is counted in slots_more=, never printed.
//
// NOT ON: a row whose text the answer already carries (a body the fold or the body slot serves holds it, also an enclosing body:
// the `.f = fn` lines are on screen). Same posture as mem= (formembers.h): the compact route, XML, the DEFAULT regime.
// RIPWIRE_NO_INIT_SLOTS (any value) turns it off: the A/B handle.
//
// COST. One pass over the reference table finds the candidate rows' Value references; the value index (the by-name resolution of
// the stored functions) is built only when one is found, so an answer with no initializer row pays one scan.

#include "forfold.h"            // fold_detail::overlapsServed — the fold's own "the answer already carries this text" reading
#include "langfacts.h"         // langFacts().memberSeparator — slot_by= names a method as its rows do
#include "infra/sortutil.h"   // svLess: the candidate-name list the cost pre-check binary-searches
#include "filter.h"             // isTestSymbol — slot_by= / slot_fields= list non-test callers first
#include "formembers.h"         // MemberNamesServed — the bodies the answer serves
#include "model.h"
#include "valuerefindex.h"      // ValueRefIndex::targetsOf — the functions a value reference may hold

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <numeric>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

// How many slot pairs one row lists; the rest is counted in slots_more= (the --callees <vs targets=> cap, kSlotTargetCap).
inline constexpr std::ptrdiff_t kForSlotCap = 16;
static_assert( kForSlotCap > 0, "a table row lists at least one slot pair" );

// The A/B switch: slots ride unless RIPWIRE_NO_INIT_SLOTS is set. The caller adds the posture (compact route, XML, default).
inline bool forInitSlotsOn()
{
    return std::getenv( "RIPWIRE_NO_INIT_SLOTS" ) == nullptr;
}

// The legend clauses, present-only beside the attribute (a row carries slots=). Terse; no "--" (an XML comment); one clause each.
inline constexpr std::string_view kForCompactInitSlotsLegend =
    "; d slots= an initializer's slot=function bindings by the index (source order, not calls), slots_more= pairs cut";
inline constexpr std::string_view kForInitSlotsLegend =
    "; slots= on a variable or constant d row: up to 16 slot=function pairs the initializer binds by the index (the slot as "
    "into= spells it less the row name, source order), a binding not a call, slots_more= the pairs not listed";
static_assert( kForCompactInitSlotsLegend.find( ';', 1 ) == std::string_view::npos && kForInitSlotsLegend.find( ';', 1 ) == std::string_view::npos,
               "one clause each: a ';' inside would split it (the legend's clause separator)" );
static_assert( kForSlotCap == 16, "kForInitSlotsLegend states the cap: move the sentence with the constant" );

namespace slot_detail
{
// One struct field of a slot_fields= run before the cap: its printed item, whether a caller was found, how many functions it holds,
// whether that caller joins by the field name alone.
struct SlotFieldItem
{
    std::string item;
    bool        hasCaller = false;
    std::size_t stored    = 0;
    bool        nameOnly  = false;   // its caller joins by the field NAME alone (`@~C`): printed, it sets the name-tier legend
};
// The slot key as into= spells it, less the row's own name: `o.run` → `run`, `po[0]` → `[0]`, `T["k"]` → `["k"]`.
inline std::string_view slotKey( std::string_view fieldName, std::string_view owner ) noexcept
{
    if( !owner.empty() && fieldName.size() > owner.size() && fieldName.starts_with( owner ) )
    {
        std::string_view rest = fieldName.substr( owner.size() );
        if( rest.front() == '.' )
        {
            rest.remove_prefix( 1 );
            return rest;
        }
        if( rest.front() == '[' )
        {
            return rest;
        }
    }
    return fieldName;
}
}   // namespace slot_detail

// The slot pairs of one row.
struct InitSlotPairs
{
    std::vector<std::string> pairs;   // "k=fn", source order, at most kForSlotCap
    std::size_t              more = 0;
};

// The pairs the Value references `refs` (all made inside `id`, reference order) bind, by the value index.
inline InitSlotPairs initSlotPairs( const IngestResult& ing, const ValueRefIndex& vri, NodeId id, const std::vector<std::uint32_t>& refs )
{
    InitSlotPairs out;
    std::vector<std::string> seen;
    for( const std::uint32_t v : refs )
    {
        const Reference&       r   = ing.references[v];
        const std::string_view key = slot_detail::slotKey( r.fieldName, ing.symbols[id].name );
        std::vector<NodeId>    tgt = vri.targetsOf( v );
        std::ranges::sort( tgt, [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].name != ing.symbols[b].name ? ing.symbols[a].name < ing.symbols[b].name : a < b; } );
        for( const NodeId t : tgt )
        {
            const std::string_view fn = ing.symbols[t].name;
            std::string pair = std::string( key ) + "=" + std::string( fn );
            if( std::ranges::find( seen, pair ) != seen.end() )
            {
                continue;   // one binding spelled twice (a by-name lookup with two same-named defs prints the name once)
            }
            seen.push_back( pair );
            const bool splits = key.empty() || fn.empty() || key.find_first_of( ",=" ) != std::string_view::npos || fn.find_first_of( ",=" ) != std::string_view::npos;
            if( !splits && std::ssize( out.pairs ) < kForSlotCap )
            {
                out.pairs.push_back( std::move( pair ) );
                continue;
            }
            ++out.more;   // cut by the count, or a pair the list's comma or '=' would split: counted, never silent
        }
    }
    return out;
}

// THE SPLICE: walk the rendered <sigs> rows (each opens `<d l=`, one per `shownIds` entry, in that order) and append
// ` slots="…"[ slots_more="N"]` to each initializer row's head. Returns the bytes added (0: `sigs` untouched). A row count that
// disagrees with `shownIds` splices nothing (the rows are not the ones the ids name).
inline std::size_t spliceInitSlots( std::string& sigs, const IngestResult& ing, const std::vector<NodeId>& shownIds, const MemberNamesServed& served )
{
    // the candidate rows: an initializer kind the answer does not already carry the text of
    std::vector<std::pair<NodeId, std::size_t>> cand;   // (symbol, row index)
    for( std::size_t i = 0; i < shownIds.size(); ++i )
    {
        const NodeId id = shownIds[i];
        // an initializer may sit on a variable, a field or an untyped binding — never a callable, an owner (mem= names those) or a section
        const SymKind k = id < ing.symbols.size() ? ing.symbols[id].kind : SymKind::Section;
        if( ( k == SymKind::Var || k == SymKind::Field || k == SymKind::Other ) && !fold_detail::overlapsServed( ing, id, served.bodies, /*orHolds=*/false ) )
        {
            cand.emplace_back( id, i );
        }
    }
    if( cand.empty() )
    {
        return 0;
    }
    // one scan: the Value references made inside a candidate (the index is built only when there is one)
    std::vector<std::vector<std::uint32_t>> refsOf( cand.size() );
    std::vector<std::pair<NodeId, std::size_t>> byId;   // (symbol, candidate index), sorted: one binary search per reference
    for( std::size_t c = 0; c < cand.size(); ++c )
    {
        byId.emplace_back( cand[c].first, c );
    }
    std::ranges::sort( byId );
    bool any = false;
    for( std::uint32_t i = 0; i < ing.references.size(); ++i )
    {
        const Reference& r = ing.references[i];
        if( r.role != RefRole::Value || r.fromSymbol == kNoNode || r.calleeName.empty() )
        {
            continue;   // a depth-cut record or a slot fact names nothing (name = "")
        }
        for( auto it = std::ranges::lower_bound( byId, std::pair<NodeId, std::size_t>{ r.fromSymbol, 0 } ); it != byId.end() && it->first == r.fromSymbol; ++it )
        {
            refsOf[it->second].push_back( i );
            any = true;
        }
    }
    if( !any )
    {
        return 0;
    }
    constexpr std::string_view kOpen = "<d l=\"";
    std::vector<std::size_t> heads;
    for( std::size_t at = sigs.find( kOpen ); at != std::string::npos; at = sigs.find( kOpen, at + kOpen.size() ) )
    {
        heads.push_back( at );
    }
    if( heads.size() != shownIds.size() )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "no row carries slots=: the answer is the one without initializer slots",
                  "spliceInitSlots: the <sigs> rows and the shown ids disagree" );
        return 0;
    }
    const ValueRefIndex vri( ing );
    std::vector<std::pair<std::size_t, std::string>> inserts;   // (offset of the head's '>', attribute run)
    std::vector<char> esc;
    for( std::size_t c = 0; c < cand.size(); ++c )
    {
        if( refsOf[c].empty() )
        {
            continue;
        }
        const InitSlotPairs sp = initSlotPairs( ing, vri, cand[c].first, refsOf[c] );
        if( sp.pairs.empty() )
        {
            continue;   // nothing resolved to a function (a slots_more= alone would claim pairs it cannot show)
        }
        std::string run = " slots=\"";
        for( std::size_t k = 0; k < sp.pairs.size(); ++k )
        {
            run += k == 0 ? "" : ",";
            run += escapeXml( sp.pairs[k], esc );
        }
        run += "\"";
        if( sp.more > 0 )
        {
            run += " slots_more=\"" + std::to_string( sp.more ) + "\"";
        }
        const std::size_t i     = cand[c].second;
        const std::size_t close = sigs.find( '>', heads[i] );
        ASSUME( close != std::string::npos && ( i + 1 == heads.size() || close < heads[i + 1] ), "a <d> head closes before the next row opens" );
        inserts.emplace_back( close, std::move( run ) );
    }
    std::ranges::sort( inserts, {}, &std::pair<std::size_t, std::string>::first );
    std::size_t added = 0;
    for( auto it = inserts.rbegin(); it != inserts.rend(); ++it )   // back to front: earlier offsets stay valid
    {
        sigs.insert( it->first, it->second );
        added += it->second.size();
    }
    return added;
}

// ── SLOT JOIN ROWS (lane fn-slot, IX1-V2) ─────────────────────────────────────────────────────────────────
// The value index's slot and container joins, on the SHOWN rows of the same posture: a function row the answer names may be
// reached through a slot it is stored in (a struct field, a variable, a registrar's parameter), which no call edge shows —
// cockroach's batcheval Put is stored by RegisterReadWriteCommand into Command.EvalRW and run by evaluateCommand's
// `cmd.EvalRW( … )`; terraform's Local.opPlan is stored in a local `f` that Local.Operation calls. On a shown row:
//   slot_by="A,B"       a Function/Method row: up to kForSlotByCap functions that MAY call it through such a slot (the --callers
//                       <vr> called_by= names, slot and container joins alike, first-site order), slot_by_more="N" the rest;
//   slot_fields="F=K@C" a struct/class row: up to kForSlotByCap of its fields that hold stored functions (by the field's declared
//                       struct type name), K the distinct functions stored there, C the first function calling through a field F
//                       (`@C` absent when none), slot_fields_more="N" the rest.
// MAY-call clues by the index, never a proven call, never in count=. RIPWIRE_NO_SLOT_JOIN_ROWS (any value) turns it off.
inline constexpr std::ptrdiff_t kForSlotByCap = 4;
inline bool forSlotJoinRowsOn()
{
    return std::getenv( "RIPWIRE_NO_SLOT_JOIN_ROWS" ) == nullptr;
}
// fix1 F-4: the mark on a caller joined by the field NAME alone, and its present-only clause (rides when a row prints the mark).
inline constexpr std::string_view kForSlotNameMark = "~";
inline constexpr std::string_view kForCompactSlotNameLegend = "; d slot_by= ~C, slot_fields= @~C: C matches the field name only (its type unread), a candidate";
inline constexpr std::string_view kForSlotNameLegend =
    "; a ~ before a slot_by= name or a slot_fields= caller (@~C): that function calls through a field of the same NAME whose struct "
    "type is not read (the callers rows say via=\"slot-name\"), a candidate, never a fact";
inline constexpr std::string_view kForCompactSlotJoinLegend =
    "; d slot_by= functions that MAY call this one through a slot it is stored in, slot_fields= F=K@C a struct field F holding K "
    "stored functions that C calls through (both by the value index, not calls), _more= the rest";
inline constexpr std::string_view kForSlotJoinLegend =
    "; slot_by= on a function d row: up to 4 functions that MAY call it through a slot it is stored in (a struct field, by type or "
    "by field name, a variable, a parameter of a registrar it is passed to), by the value index, never a proven call, "
    "slot_by_more= the rest, and slot_fields= on a struct d row: up to 4 fields holding stored functions as F=K@C, K distinct "
    "functions stored in F, C the first function calling through a field F (absent when none), slot_fields_more= the rest";
static_assert( kForCompactSlotJoinLegend.find( ';', 1 ) == std::string_view::npos && kForSlotJoinLegend.find( ';', 1 ) == std::string_view::npos
                   && kForSlotJoinLegend.find( "--" ) == std::string_view::npos && kForCompactSlotJoinLegend.find( "--" ) == std::string_view::npos,
               "one clause each, and no '--' (the legend is an XML comment)" );
static_assert( kForSlotByCap == 4, "kForSlotJoinLegend states the cap: move the sentence with the constant" );
static_assert( kForCompactSlotNameLegend.find( ';', 1 ) == std::string_view::npos && kForSlotNameLegend.find( ';', 1 ) == std::string_view::npos
                   && kForCompactSlotNameLegend.find( "--" ) == std::string_view::npos && kForSlotNameLegend.find( "--" ) == std::string_view::npos,
               "one clause each, and no '--' (the legend is an XML comment)" );

namespace slot_detail
{
// Appends `name` to `names` once, counting it in `more` past the cap; a name a comma would split is counted, never printed.
inline void addCapped( std::vector<std::string>& names, std::size_t& more, std::string name )
{
    if( name.empty() || std::ranges::find( names, name ) != names.end() )
    {
        return;
    }
    if( std::ssize( names ) < kForSlotByCap && name.find_first_of( ",=@" ) == std::string::npos )
    {
        names.push_back( std::move( name ) );
        return;
    }
    ++more;
}
// A caller as the <sigs> rows name it: the owner joined (`Local.Operation`, `Editor::run`), so two same-named methods of two
// types (terraform's Local.Operation and Cloud.Operation) never read as one.
inline std::string ownerName( const Symbol& s )
{
    if( s.scope.empty() )
    {
        return s.name;
    }
    return s.scope + std::string( langFacts( s.lang ).memberSeparator ) + s.name;   // the language's own (`Local.Operation`, `Editor::run`)
}
inline std::string joinedRun( std::string_view attr, const std::vector<std::string>& names, std::size_t more, std::vector<char>& esc )
{
    std::string run = " " + std::string( attr ) + "=\"";
    for( std::size_t k = 0; k < names.size(); ++k )
    {
        run += k == 0 ? "" : ",";
        run += escapeXml( names[k], esc );
    }
    run += "\"";
    if( more > 0 )
    {
        run += " " + std::string( attr ) + "_more=\"" + std::to_string( more ) + "\"";
    }
    return run;
}
}   // namespace slot_detail

// THE SPLICE, as spliceInitSlots: appends slot_by= / slot_fields= to the shown rows' heads. Returns the bytes added.
// `nameTier` (when given) is set when a printed caller joined by the field NAME alone (the `~` mark).
inline std::size_t spliceSlotJoinRows( std::string& sigs, const IngestResult& ing, const std::vector<NodeId>& shownIds, bool* nameTier = nullptr )
{
    std::vector<std::size_t> cand;
    for( std::size_t i = 0; i < shownIds.size(); ++i )
    {
        const SymKind k = shownIds[i] < ing.symbols.size() ? ing.symbols[ shownIds[i] ].kind : SymKind::Section;
        if( k == SymKind::Function || k == SymKind::Method || k == SymKind::Class || isStructOrNamedType( k ) )
        {
            cand.push_back( i );
        }
    }
    if( cand.empty() )
    {
        return 0;
    }
    // COST: the value index is built only when some Value reference can join a candidate — it names a candidate function, or it
    // is stored into a struct-field slot (a struct row's slot_fields=) — so an answer with none pays one scan, no index.
    std::vector<std::string_view> fnNames;
    bool                          structRow = false;
    for( const std::size_t i : cand )
    {
        const Symbol& s = ing.symbols[ shownIds[i] ];
        if( s.kind == SymKind::Function || s.kind == SymKind::Method )
        {
            fnNames.push_back( s.name );
        }
        else
        {
            structRow = true;
        }
    }
    std::ranges::sort( fnNames, rw::sortutil::svLess );
    const bool joinable = std::ranges::any_of( ing.references, [ & ]( const Reference& r )
    {
        return r.role == RefRole::Value
            && ( std::ranges::binary_search( fnNames, std::string_view( r.calleeName ), rw::sortutil::svLess )
                 || ( structRow && ( !r.memberPath.empty() || ( !r.qualifier.empty() && r.qualifier[0] == kValueRefSlotParamScope ) ) ) );
    } );
    if( !joinable )
    {
        return 0;
    }
    constexpr std::string_view kOpen = "<d l=\"";
    std::vector<std::size_t> heads;
    for( std::size_t at = sigs.find( kOpen ); at != std::string::npos; at = sigs.find( kOpen, at + kOpen.size() ) )
    {
        heads.push_back( at );
    }
    if( heads.size() != shownIds.size() )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "no row carries slot_by=: the answer is the one without slot join rows",
                  "spliceSlotJoinRows: the <sigs> rows and the shown ids disagree" );
        return 0;
    }
    // fix1 (RSS): the NARROW index (ValueRefIndex::narrowFor) — the shown functions' values and every slot store, not the whole
    // tree's value references. RIPWIRE_SLOT_INDEX_FULL (any value) builds the full one: the A/B handle that proves the rows equal.
    const ValueRefIndex vri = std::getenv( "RIPWIRE_SLOT_INDEX_FULL" ) == nullptr ? ValueRefIndex::narrowFor( ing, fnNames ) : ValueRefIndex( ing );
    std::vector<std::pair<std::size_t, std::string>> inserts;
    std::vector<char> esc;
    for( const std::size_t i : cand )
    {
        const NodeId   id = shownIds[i];
        const Symbol&  s  = ing.symbols[id];
        std::vector<std::string> names;
        std::size_t              more = 0;
        bool                     printedNameOnly = false;   // a caller joined by the field NAME alone is in the printed run (not a `~` in some name)
        std::string              run;
        if( s.kind == SymKind::Function || s.kind == SymKind::Method )
        {
            const bool         subjectIsTest = isTestSymbol( ing, id );
            const ValueRefRows rows = valueRefCallerRows( ing, vri, std::span<const NodeId>( &id, 1 ) );
            std::vector<std::tuple<bool, bool, std::string>> by;   // (a test caller, a field-name-only caller, name), first-site order; non-test callers listed first
            for( const ValueRefRow& row : rows.rows )
            {
                if( !subjectIsTest && isTestPath( rootRelPath( ing, ing.references[ row.ref ].fileId ) ) )
                {
                    continue;   // fix1 F-7: a store in test code (`assertMatch( t, MatchV1 )`) is a test harness, not the subject's dispatch
                }
                for( const NodeId f : vri.calledBy( row.ref ) )
                {
                    by.emplace_back( isTestSymbol( ing, f ), false, slot_detail::ownerName( ing.symbols[f] ) );
                }
                for( const std::uint32_t c : row.slotCalls )
                {
                    const NodeId from = ing.references[c].fromSymbol;
                    if( from < ing.symbols.size() )
                    {
                        // fix1 F-4: `~` marks a caller joined by the field NAME alone (via="slot-name"): a candidate, not a fact
                        by.emplace_back( isTestSymbol( ing, from ), !row.slotTyped, ( row.slotTyped ? "" : std::string( kForSlotNameMark ) ) + slot_detail::ownerName( ing.symbols[from] ) );
                    }
                }
            }
            std::ranges::stable_partition( by, []( const auto& b ) { return !std::get<0>( b ); } );
            for( auto& [ test, nameOnly, name ] : by )
            {
                const std::size_t before = names.size();
                slot_detail::addCapped( names, more, std::move( name ) );
                printedNameOnly = printedNameOnly || ( nameOnly && names.size() > before );   // CR 4396503829: the mark of a PRINTED name-only caller
            }
            if( !names.empty() )
            {
                run = slot_detail::joinedRun( "slot_by", names, more, esc );
            }
        }
        else
        {
            std::vector<std::pair<std::string_view, std::vector<std::uint32_t>>> fields;   // field → its value refs, first-seen order
            const std::string typeKey = slotKeysOwnTypes( s.lang ) ? vri.slots().typeKeyOf( id ) : s.name;   // fix1 F-2: the ONE key
            for( const auto& [ ref, field ] : vri.slots().valuesOfType( typeKey ) )
            {
                auto it = std::ranges::find( fields, field, &std::pair<std::string_view, std::vector<std::uint32_t>>::first );
                if( it == fields.end() )
                {
                    fields.emplace_back( field, std::vector<std::uint32_t>{} );
                    it = fields.end() - 1;
                }
                it->second.push_back( ref );
            }
            std::vector<slot_detail::SlotFieldItem> items;
            for( const auto& [ field, refs ] : fields )
            {
                std::vector<NodeId> fns;
                std::string         caller;
                bool                callerIsTest = false;
                bool                callerTyped  = false;
                for( const std::uint32_t r : refs )
                {
                    std::ranges::copy( vri.targetsOf( r ), std::back_inserter( fns ) );
                    for( const SlotIndex::Hit& h : vri.slots().callsFor( r ) )
                    {
                        const NodeId from = ing.references[h.ref].fromSymbol;
                        if( from >= ing.symbols.size() )
                        {
                            continue;
                        }
                        const bool test = isTestSymbol( ing, from );
                        // the first non-test caller, else the first caller; a same-type caller before a field-name one
                        if( caller.empty() || ( callerIsTest && !test ) || ( callerIsTest == test && !callerTyped && h.typed ) )
                        {
                            caller       = slot_detail::ownerName( ing.symbols[from] );
                            callerIsTest = test;
                            callerTyped  = h.typed;
                        }
                    }
                }
                std::ranges::sort( fns );
                fns.erase( std::ranges::unique( fns ).begin(), fns.end() );
                if( fns.empty() || caller.find_first_of( ",=@" ) != std::string::npos )
                {
                    ++more;
                    continue;
                }
                // fix1 F-4: `@~C` — C joins by the field NAME alone (its receiver's type is not read): a candidate, not a fact
                items.push_back( { std::string( field ) + "=" + std::to_string( fns.size() )
                                       + ( caller.empty() ? "" : "@" + ( callerTyped ? std::string() : std::string( kForSlotNameMark ) ) + caller ),
                                   !caller.empty(), fns.size(), !callerTyped && !caller.empty() } );
            }
            // fix1 F-4: the cap is a spew guard, so it cuts the LEAST informative fields: a field with a caller first, then the most
            // stored functions, then the name (`writeField=11@Row_display` is never cut for `isVisible=1`). The kept fields print in
            // their first-seen order, as before.
            std::vector<std::size_t> rank( items.size() );
            std::iota( rank.begin(), rank.end(), std::size_t{ 0 } );
            std::ranges::stable_sort( rank, [ & ]( std::size_t x, std::size_t y )
            {
                const slot_detail::SlotFieldItem& a = items[x];
                const slot_detail::SlotFieldItem& b = items[y];
                return a.hasCaller != b.hasCaller ? a.hasCaller : ( a.stored != b.stored ? a.stored > b.stored : a.item < b.item );
            } );
            const std::size_t keep = std::min<std::size_t>( items.size(), static_cast<std::size_t>( kForSlotByCap ) );
            std::ranges::sort( rank.begin(), rank.begin() + static_cast<std::ptrdiff_t>( keep ) );
            for( std::size_t k = 0; k < keep; ++k )
            {
                printedNameOnly = printedNameOnly || items[ rank[k] ].nameOnly;   // CR 4396503829: the mark of a PRINTED name-only caller
                names.push_back( std::move( items[ rank[k] ].item ) );
            }
            more += items.size() - keep;
            if( !names.empty() )
            {
                run = slot_detail::joinedRun( "slot_fields", names, more, esc );
            }
        }
        if( run.empty() )
        {
            continue;
        }
        if( nameTier != nullptr && printedNameOnly )
        {
            *nameTier = true;
        }
        const std::size_t close = sigs.find( '>', heads[i] );
        ASSUME( close != std::string::npos && ( i + 1 == heads.size() || close < heads[i + 1] ), "a <d> head closes before the next row opens" );
        inserts.emplace_back( close, std::move( run ) );
    }
    std::size_t added = 0;
    for( auto it = inserts.rbegin(); it != inserts.rend(); ++it )   // cand is in row order: back to front keeps offsets valid
    {
        sigs.insert( it->first, it->second );
        added += it->second.size();
    }
    return added;
}

}   // namespace rw
