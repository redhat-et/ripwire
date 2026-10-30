#pragma once
// valuerefs.h — the ONE resolution of reference-as-value rows (RefRole::Value / RefRole::Through, captured by
// src/ingest_valuerefs.h), shared by every surface that discloses them: --callers/--callees and their MCP twins
// (callhierarchy.h), --impact, --safe-delete, --dead-code, --uses and --path.
//
// WHAT A ROW IS, AND IS NOT. A <vr> row says a function is USED AS A VALUE at bind= — stored into a table, field or
// variable, or passed as an argument — and names where it lands (into=). It is NOT a call: the call, if any, happens
// wherever the slot is later invoked. called_by= (callers side) and through= (callees side) name a function that MAY
// call through that slot — a called parameter, or a `tbl[k](…)` / `tbl.k(…)` on the same declaration — a clue an
// agent can follow, never a proven call. No count= / reaches= / callers= / impact_reaches= ever includes a row.
//
// MATCHED BY NAME, with the call graph's visibility: a definition in the reference's own file wins; otherwise a
// C/C++ definition with external linkage (a `static` one is reachable only from its own file), a Go definition in
// the same package directory, or a JS/TS/Python definition the file imports by that very name. A file-scope
// non-function declaration of the same name in the reference's file hides every definition elsewhere. Only
// functions and methods are targets (a class used as a value is out of scope).

#include "valuerefindex.h"      // ValueRefIndex, the rows, the --uses filter (the resolution core)
#include "graphlegend.h"       // countFieldOrEmpty — the absent-at-zero count spelling
#include "model.h"
#include "nextverb.h"     // nextFlag — the <pd> callees row's next=
#include "sarif.h"
#include "serialize.h"   // escapeXml / jsonStr

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// ── rendering ────────────────────────────────────────────────────────────────────────────────────────────────
// The callee a slot call writes: a C-family slot Through keeps it whole (fieldName); an IX1-V2 member call (an ordinary Call
// reference, valuerefindex.h addMemberCalls) is rebuilt from its receiver chain (`cmd.EvalRW`, `s.cfg.Run`).
inline std::string slotCallWritten( const Reference& r )
{
    if( r.role != RefRole::Call )
    {
        return r.fieldName;
    }
    std::string out = r.memberRoot;
    if( !r.memberPath.empty() )
    {
        out += ( out.empty() ? "" : "." ) + r.memberPath;
    }
    return out + "." + r.calleeName;
}
struct VrRender
{
    bool             singleRoot = true;
    std::string_view rootPrefix;
};

inline std::string vrPath( const IngestResult& ing, std::uint32_t fileId, const VrRender& rr )
{
    return std::string( rr.singleRoot ? sarif::rootRelativeUri( ing.files[fileId], rr.rootPrefix ) : std::string_view( ing.files[fileId] ) );
}

// IX-1: the slot callers of one callers-side <vr> row as (attribute, value) pairs, in order — called_by= names and called_at=
// sites (file:line), one per calling function in the same order, cut at kSlotCallerCap with called_more= the rest; via= the
// tier; slot_name_also= the name-only callers a same-type tier hides. Empty when a container/parameter join already answers
// (called_by= is then that join's) or the slot has no caller.
inline constexpr std::size_t kSlotCallerCap = 8;
inline std::vector<std::pair<std::string_view, std::string>> slotCallerFields( const IngestResult& ing, const ValueRefRow& row, const VrRender& rr, bool callersSide )
{
    std::vector<std::pair<std::string_view, std::string>> out;
    if( !callersSide || !row.calledBy.empty() || row.slotCalls.empty() )
    {
        return out;
    }
    std::string       by, at;
    const std::size_t shown = std::min( row.slotCalls.size(), kSlotCallerCap );
    for( std::size_t k = 0; k < shown; ++k )
    {
        const Reference& c = ing.references[ row.slotCalls[k] ];
        by += ( k == 0 ? "" : "," ) + ing.symbols[ c.fromSymbol ].name;
        at += ( k == 0 ? "" : "," ) + vrPath( ing, c.fileId, rr ) + ":" + std::to_string( c.line );
    }
    out.emplace_back( "called_by", std::move( by ) );
    out.emplace_back( "called_at", std::move( at ) );
    out.emplace_back( "via", row.slotTyped ? "slot" : "slot-name" );
    if( shown < row.slotCalls.size() )
    {
        out.emplace_back( "called_more", std::to_string( row.slotCalls.size() - shown ) );
    }
    if( row.slotNameAlso > 0 )
    {
        out.emplace_back( "slot_name_also", std::to_string( row.slotNameAlso ) );
    }
    if( row.slotCands > 1 )
    {
        out.emplace_back( "cands", std::to_string( row.slotCands ) );   // IX1-V2: the slot is a table of K functions, not this one alone
    }
    return out;
}

// The default display window of the <vrs> rows (the runaway guard): value_refs= and total= stay whole, the rows
// beyond it are counted (capped="1") and the next= verb (--uses=SYM) pages every site. It lives beside the two
// renderers that apply it and emit that disclosure (valueRefsXml, valueRefsJson).
inline constexpr std::size_t kValueRefRowCap = 64;

// The <vrs total= shown= capped= [next=]> window and its rows, or "" when there is no row (byte identity).
inline std::string valueRefsXml( const IngestResult& ing, const ValueRefRows& rows, bool callersSide, const VrRender& rr,
                                 std::string_view nextVerb, std::size_t cap = kValueRefRowCap )
{
    if( rows.rows.empty() )
    {
        return {};
    }
    EXPECTS( cap > 0, "a window of zero rows would cut every row while saying shown=0 — the cap is a runaway guard, never a hide" );
    const std::size_t total = rows.rows.size();
    const std::size_t shown = std::min( total, cap );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    std::string out = "<vrs total=\"" + std::to_string( total ) + "\" shown=\"" + std::to_string( shown ) + "\" capped=\"" + ( shown < total ? "1" : "0" ) + "\"";
    if( shown < total && !nextVerb.empty() )
    {
        out += " next=\"" + ex( nextVerb ) + "\"";
    }
    out += ">";
    for( std::size_t i = 0; i < shown; ++i )
    {
        const ValueRefRow& row = rows.rows[i];
        const Reference&   r   = ing.references[row.ref];
        out += "<vr";
        if( callersSide )
        {
            if( row.in != kNoNode )
            {
                out += " in_id=\"" + ex( ing.symbols[row.in].name ) + "\"";
            }
        }
        else
        {
            const Symbol& t = ing.symbols[row.to];
            out += " to=\"" + ex( t.name ) + "\" def=\"" + ex( vrPath( ing, t.fileId, rr ) ) + ":" + std::to_string( t.line ) + "\"";
        }
        out += " bind=\"" + ex( vrPath( ing, r.fileId, rr ) ) + ":" + std::to_string( r.line ) + "\"";
        out += " into=\"" + ex( r.fieldName ) + "\"";
        if( callersSide && !row.calledBy.empty() )
        {
            out += " called_by=\"" + ex( row.calledBy ) + "\"";
        }
        for( const auto& [ k, v ] : slotCallerFields( ing, row, rr, callersSide ) )
        {
            out += " " + std::string( k ) + "=\"" + ex( v ) + "\"";   // IX-1: called_by= called_at= via= (only when called_by= above is absent)
        }
        if( !callersSide && !row.through.empty() )
        {
            out += " through=\"" + ex( row.through ) + "\"";
        }
        if( !callersSide && row.sites > 1 )
        {
            out += " sites=\"" + std::to_string( row.sites ) + "\"";
        }
        out += "/>";
    }
    out += "</vrs>";
    return out;
}

// The JSON twin: `,"KEY":{"total":N,"shown":M,"capped":0|1[,"next":"…"],"rows":[{…}]}`, or "" when there is no row.
inline std::string valueRefsJson( const IngestResult& ing, const ValueRefRows& rows, bool callersSide, const VrRender& rr,
                                  std::string_view key, std::string_view nextVerb, std::size_t cap = kValueRefRowCap )
{
    if( rows.rows.empty() )
    {
        return {};
    }
    const std::size_t total = rows.rows.size();
    const std::size_t shown = std::min( total, cap );
    std::string out = ",\"" + std::string( key ) + "\":{\"total\":" + std::to_string( total ) + ",\"shown\":" + std::to_string( shown )
                    + ",\"capped\":" + ( shown < total ? "1" : "0" );
    if( shown < total && !nextVerb.empty() )
    {
        out += ",\"next\":\"" + jsonStr( nextVerb ) + "\"";
    }
    out += ",\"rows\":[";
    for( std::size_t i = 0; i < shown; ++i )
    {
        const ValueRefRow& row = rows.rows[i];
        const Reference&   r   = ing.references[row.ref];
        out += i == 0 ? "{" : ",{";
        bool first = true;
        const auto kv = [ & ]( std::string_view k, std::string_view v )
        {
            out += first ? "\"" : ",\"";
            first = false;
            out.append( k );
            out += "\":\"" + jsonStr( v ) + "\"";
        };
        if( callersSide )
        {
            if( row.in != kNoNode )
            {
                kv( "in_id", ing.symbols[row.in].name );
            }
        }
        else
        {
            const Symbol& t = ing.symbols[row.to];
            kv( "to", t.name );
            kv( "def", vrPath( ing, t.fileId, rr ) + ":" + std::to_string( t.line ) );
        }
        kv( "bind", vrPath( ing, r.fileId, rr ) + ":" + std::to_string( r.line ) );
        kv( "into", r.fieldName );
        if( callersSide && !row.calledBy.empty() )
        {
            kv( "called_by", row.calledBy );
        }
        for( const auto& [ k, v ] : slotCallerFields( ing, row, rr, callersSide ) )
        {
            kv( k, v );   // IX-1: the XML row's slot attributes, same names
        }
        if( !callersSide && !row.through.empty() )
        {
            kv( "through", row.through );
        }
        if( !callersSide && row.sites > 1 )
        {
            kv( "sites", std::to_string( row.sites ) );
        }
        out += "}";
    }
    out += "]}";
    return out;
}

// The depth cut over the answered definitions (ValueRefRows::depthCut, ingest_valuerefs.h kVrMaxDepth): files of their
// language family whose value walk stopped at the cap — value_refs_depth_capped="N" — and the first cut, file:line —
// value_refs_depth_at=. "" when there is none, so an answer over an uncut tree is byte-identical.
inline std::string valueRefsDepthAttrXml( const IngestResult& ing, const ValueRefIndex::DepthCuts& cut, const VrRender& rr )
{
    if( cut.files == 0 )
    {
        return {};
    }
    EXPECTS( cut.first < ing.references.size(), "a depth cut counted over N > 0 files names its first record" );
    const Reference&  r = ing.references[cut.first];
    std::vector<char> esc;
    return " value_refs_depth_capped=\"" + std::to_string( cut.files ) + "\" value_refs_depth_at=\""
         + std::string( escapeXml( vrPath( ing, r.fileId, rr ) + ":" + std::to_string( r.line ), esc ) ) + "\"";
}
inline std::string valueRefsDepthKeyJson( const IngestResult& ing, const ValueRefIndex::DepthCuts& cut, const VrRender& rr )
{
    if( cut.files == 0 )
    {
        return {};
    }
    EXPECTS( cut.first < ing.references.size(), "a depth cut counted over N > 0 files names its first record" );
    const Reference& r = ing.references[cut.first];
    return ",\"value_refs_depth_capped\":" + std::to_string( cut.files ) + ",\"value_refs_depth_at\":\""
         + jsonStr( vrPath( ing, r.fileId, rr ) + ":" + std::to_string( r.line ) ) + "\"";
}

// The candidate window the callees-side dispatch rows share (IX-3 <pd>, IX-1 <vs>): ` COUNT="N" shown="M"[ next="…"]>` (next=
// only when cut) and the first `cap` targets as <t n= p=> (a member's n= is Scope.name).
inline std::string vrTargetWindowXml( const IngestResult& ing, std::span<const NodeId> targets, std::size_t cap, std::string_view countName,
                                      std::string_view nextIfCut, const VrRender& rr, std::vector<char>& esc )
{
    const std::size_t shown = std::min( targets.size(), cap );
    std::string out = " " + std::string( countName ) + "=\"" + std::to_string( targets.size() ) + "\" shown=\"" + std::to_string( shown ) + "\"";
    if( shown < targets.size() )
    {
        out += " next=\"" + std::string( escapeXml( nextIfCut, esc ) ) + "\"";
    }
    out += ">";
    for( const NodeId id : targets.first( shown ) )
    {
        const Symbol& t = ing.symbols[id];
        out += "<t n=\"" + std::string( escapeXml( t.scope.empty() ? t.name : t.scope + "." + t.name, esc ) ) + "\" p=\""
             + std::string( escapeXml( vrPath( ing, t.fileId, rr ), esc ) ) + ":" + std::to_string( t.line ) + "\"/>";
    }
    return out;
}

// ── IX-1 slot-type join: the callees side ───────────────────────────────────────────────────────────────
// One <vs> per call through a struct field in the answered body: l= its line, through= the written callee, slot= the
// resolved Type.field, via=, targets= the distinct functions that slot may hold, the first kSlotTargetCap as <t n= p=>,
// next= when cut (a designated store is found by the regex `(.|->)f\s*=[^=]`; a positional one by --uses on the first unshown).
inline constexpr std::size_t kSlotTargetCap = 16;
// The <vs> continuation when its window is cut (checklist 34: through nextFlag): a designated store is found by the regex
// `(.|->)f\s*=[^=]` (any spacing, a field assignment too); otherwise --uses on the first function the window does not show.
inline std::string slotSiteNext( const IngestResult& ing, const SlotSiteRow& site )
{
    const std::size_t shown = std::min( site.targets.size(), kSlotTargetCap );
    if( site.anyDesignated )
    {
        // a regex, not the literal `.f =`: an aligned (`.f    = fn`) or unspaced (`.f=fn`) store is a store too, and `x->f = fn` another
        return nextFlag( "--regex=", "(\\.|->)" + site.slot.substr( site.slot.rfind( '.' ) + 1 ) + "\\s*=[^=]" );
    }
    return shown < site.targets.size() ? nextFlag( "--uses=", ing.symbols[ site.targets[shown] ].name ) : std::string();
}
inline std::string slotCalleesXml( const IngestResult& ing, std::span<const SlotSiteRow> sites, const VrRender& rr )
{
    std::string       out;
    std::vector<char> esc;
    for( const SlotSiteRow& site : sites )
    {
        const Reference& r = ing.references[ site.ref ];
        out += "<vs l=\"" + std::to_string( r.line ) + "\" through=\"" + std::string( escapeXml( slotCallWritten( r ), esc ) ) + "\" slot=\""
             + std::string( escapeXml( site.slot, esc ) ) + "\" via=\"" + ( site.typed ? "slot" : "slot-name" ) + "\"";
        out += site.nameAlso > 0 ? " slot_name_also=\"" + std::to_string( site.nameAlso ) + "\"" : std::string();   // L-1: name-only stores the typed tier hides
        out += vrTargetWindowXml( ing, site.targets, kSlotTargetCap, "targets", slotSiteNext( ing, site ), rr, esc ) + "</vs>";
    }
    return out;
}
// The --json twin: `,"vss":[{"l":N,"through":…,"slot":…,"via":…,"targets":N,"shown":M[,"next":…],"t":[{"n":…,"p":…}]}]`, or "".
inline std::string slotCalleesJson( const IngestResult& ing, std::span<const SlotSiteRow> sites, const VrRender& rr )
{
    if( sites.empty() )
    {
        return {};
    }
    std::string out = ",\"vss\":[";
    for( std::size_t i = 0; i < sites.size(); ++i )
    {
        const SlotSiteRow& site  = sites[i];
        const Reference&   r     = ing.references[ site.ref ];
        const std::size_t  shown = std::min( site.targets.size(), kSlotTargetCap );
        out += ( i == 0 ? "{" : ",{" );
        out += "\"l\":" + std::to_string( r.line ) + ",\"through\":\"" + jsonStr( slotCallWritten( r ) ) + "\",\"slot\":\"" + jsonStr( site.slot )
             + "\",\"via\":\"" + ( site.typed ? "slot" : "slot-name" ) + "\"" + ( site.nameAlso > 0 ? ",\"slot_name_also\":" + std::to_string( site.nameAlso ) : std::string() )
             + ",\"targets\":" + std::to_string( site.targets.size() ) + ",\"shown\":" + std::to_string( shown );
        if( shown < site.targets.size() )
        {
            out += ",\"next\":\"" + jsonStr( slotSiteNext( ing, site ) ) + "\"";
        }
        out += ",\"t\":[";
        for( std::size_t k = 0; k < shown; ++k )
        {
            const Symbol& t = ing.symbols[ site.targets[k] ];
            out += ( k == 0 ? "{\"n\":\"" : ",{\"n\":\"" ) + jsonStr( t.scope.empty() ? t.name : t.scope + "." + t.name ) + "\",\"p\":\"" + jsonStr( vrPath( ing, t.fileId, rr ) + ":" + std::to_string( t.line ) ) + "\"}";
        }
        out += "]}";
    }
    return out + "]";
}
inline std::string slotCallsAttrXml( std::size_t n ) { return countFieldOrEmpty( "slot_calls", n, /*json=*/false ); }
inline std::string slotCallsKeyJson( std::size_t n ) { return countFieldOrEmpty( "slot_calls", n, /*json=*/true ); }
// The legend clause, exactly when an answer carries a slot join: callers — a <vr> row with via= (ValueRefRows::slotCallers);
// callees — slot_calls=.
inline constexpr std::string_view slotJoinClause( bool callersSide ) noexcept
{
    return callersSide
        ? "vr called_by= called_at= via=slot|slot-name: the function was stored in a struct FIELD; called_by names each function "
          "that calls through a field of that name (x->f(...)), called_at= its first such call, file:line, in the same order. "
          "Not read: a cast, call-result or this-> receiver; a positional entry joins only when its file holds the struct body "
          "and its index is exact. "
          "via=slot: both sides' declared struct types are the same (one tag with the same body text in two files is one type); via=slot-name: the field name alone matched (one side's "
          "struct type unknown), the lower tier, shown only when no same-type call exists (slot_name_also=K: K name-only "
          "callers hidden behind it); two known, different types never join. called_more=N: N more callers past the first 8. "
          "MAY call through the slot; never a proven call, never in count=/callers=/reaches=. "
        : "slot_calls=N (absent when 0): N calls in this body go through a struct FIELD holding a function (x->f(...)). "
          "<vs l= through= slot=Type.field via= targets=K shown=> lists the functions stored in that field anywhere "
          "(designated .f = fn, a positional entry whose file holds the struct body, x->f = fn; a cast, call-result or this-> "
          "receiver is not read), first 16 as <t n= p=>, next= the rest; slot=@N.f: an "
          "anonymous struct declared at line N of this file. via=slot: same declared struct type (one tag with the same body text "
          "in two files is one type); via=slot-name: field name "
          "only (one side's type unknown; slot_name_also=K: K such functions the same-type ones hide). MAY be called; never a proven call, never in count=. ";
}

inline std::string slotJoinLegend( bool any, bool callersSide, bool cands = false )
{
    if( !any )
    {
        return {};
    }
    std::string out( slotJoinClause( callersSide ) );
    if( callersSide && cands )
    {
        out += "cands=K: the first called_by call's slot holds K distinct functions, this one among them (a table: which one runs "
               "is decided at run time). ";
    }
    return out;
}

// ── IX-3 name-template dispatch rows ────────────────────────────────────────────────────────────────────
// The callers-side window (--callers / --safe-delete / --impact of a method a template can name): one <pd> per site,
// in reference order, cut at kPatternRowCap (the per-method reach measured at median 1, max 2 on the census trees).
inline constexpr std::size_t kPatternRowCap = 8;
inline std::string patternSiteAttrs( const IngestResult& ing, const Reference& r, const VrRender& rr, std::vector<char>& esc )
{
    const auto ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    std::string out;
    if( r.fromSymbol < ing.symbols.size() )
    {
        out += " in=\"" + ex( ing.symbols[ r.fromSymbol ].name ) + "\"";
    }
    out += " p=\"" + ex( vrPath( ing, r.fileId, rr ) ) + ":" + std::to_string( r.line ) + "\" pattern=\"" + ex( r.calleeName ) + "\"";
    return out;
}
// `wide`: the too-wide sites (--safe-delete, when they back risk=hedged) as <pdws>/<pdw>: the site only, no candidate list.
inline std::string patternDispatchXml( const IngestResult& ing, std::span<const std::uint32_t> sites, const VrRender& rr, bool wide = false )
{
    if( sites.empty() )
    {
        return {};
    }
    const std::string_view tag   = wide ? "pdw" : "pd";
    const std::size_t      shown = std::min( sites.size(), kPatternRowCap );
    std::vector<char> esc;
    std::string out = "<" + std::string( tag ) + "s total=\"" + std::to_string( sites.size() ) + "\" shown=\"" + std::to_string( shown ) + "\">";
    for( std::size_t i = 0; i < shown; ++i )
    {
        out += "<" + std::string( tag ) + patternSiteAttrs( ing, ing.references[ sites[i] ], rr, esc ) + "/>";
    }
    return out + "</" + std::string( tag ) + "s>";
}
// The dispatcher side (--callees of the function that holds the template): one <pd> per site with cands= (every member
// it can name), the first kPatternRowCap of them as <t> rows, and next= (the callers verb on one of them) when cut.
inline std::string patternCalleesXml( const IngestResult& ing, const PatternIndex& pix, std::span<const std::uint32_t> sites, const VrRender& rr )
{
    std::string       out;
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    for( const std::uint32_t i : sites )
    {
        const Reference&          r     = ing.references[i];
        const std::vector<NodeId> cands = pix.targets( i );
        out += "<pd l=\"" + std::to_string( r.line ) + "\" pattern=\"" + ex( r.calleeName ) + "\"";
        out += vrTargetWindowXml( ing, cands, kPatternRowCap, "cands", nextFlag( "--grep=", r.fieldName.empty() ? r.composeRel : r.fieldName ), rr, esc )   // checklist 34: through nextFlag
             + "</pd>";
    }
    return out;
}
inline std::string patternDispatchAttrXml( std::size_t n, std::size_t tooWide )
{
    return countFieldOrEmpty( "pattern_dispatch", n, /*json=*/false ) + countFieldOrEmpty( "pattern_too_wide", tooWide, /*json=*/false );
}
// The --json twin: the same two counts, absent at zero, beside value_refs on the --callers/--impact JSON roots.
inline std::string patternDispatchKeyJson( std::size_t n, std::size_t tooWide )
{
    return countFieldOrEmpty( "pattern_dispatch", n, /*json=*/true ) + countFieldOrEmpty( "pattern_too_wide", tooWide, /*json=*/true );
}
// The callers-side clause up to its too-wide tail: one copy for both tails.
inline constexpr std::string_view kPatternDispatchCallersLegend =
    "pattern_dispatch=N (absent when 0): N lookups build a NAME from a template (Python getattr/hasattr/__dict__.get with an "
    "f-string or +, a JS/TS o['p' + x] / o[`p${x}`]) whose literal prefix/suffix this method's name matches; a self/this/cls "
    "receiver in a method the index places in a class keeps only that class family (ancestors and subclasses, by base name). MAY be invoked through that name; matched by name, "
    "not a proven call: never in callers=/impact_reaches=/count=, and the dead-code list is unchanged. <pds>/<pd in= p= "
    "pattern=> list them. pattern_too_wide=K: K templates whose literal side is under 3 identifier characters "
    "(f\"_{m}\") could also name it; ";
// The legend clause, exactly when an answer carries pattern_dispatch= or pattern_too_wide=. `wideRows`: the answer lists
// the too-wide sites as <pdw> rows (--safe-delete, risk=hedged).
inline std::string patternDispatchLegend( bool any, bool callersSide, bool wideRows = false )
{
    if( any && !callersSide )
    {
        return "pattern_dispatch=N (absent when 0): N lookups in this body build a NAME from a template (Python getattr/hasattr/"
               "__dict__.get with an f-string or +, a JS/TS o['p' + x] / o[`p${x}`]); each <pd l= pattern= cands=K shown=> lists the "
               "class members whose names match it (a self/this/cls receiver in a method the index places in a class: that class family only), first 8 as <t n= p=>, next= the "
               "literal scan for the rest. MAY be invoked; matched by name, not a proven call: never in count=. ";
    }
    if( !any )
    {
        return {};
    }
    return std::string( kPatternDispatchCallersLegend )
         + ( wideRows ? "no candidate list, but with no other evidence they keep risk= from none-found and <pdws>/<pdw in= p= pattern=> name each site. "
                      : "no row. " );
}

inline std::string valueRefsCountAttrXml( std::size_t n ) { return countFieldOrEmpty( "value_refs", n, /*json=*/false ); }
inline std::string valueRefsCountKeyJson( std::size_t n ) { return countFieldOrEmpty( "value_refs", n, /*json=*/true ); }
// The legend clause for the depth attributes, exactly when an answer about these rows carries them.
inline const char* valueRefsDepthLegendFor( const ValueRefRows& rows ) noexcept
{
    return valueRefsDepthLegend( rows.depthCut.files > 0 );
}

}   // namespace rw

