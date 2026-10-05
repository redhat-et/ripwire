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
struct VrRender
{
    bool             singleRoot = true;
    std::string_view rootPrefix;
};

inline std::string vrPath( const IngestResult& ing, std::uint32_t fileId, const VrRender& rr )
{
    return std::string( rr.singleRoot ? sarif::rootRelativeUri( ing.files[fileId], rr.rootPrefix ) : std::string_view( ing.files[fileId] ) );
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

inline std::string valueRefsCountAttrXml( std::size_t n ) { return countFieldOrEmpty( "value_refs", n, /*json=*/false ); }
inline std::string valueRefsCountKeyJson( std::size_t n ) { return countFieldOrEmpty( "value_refs", n, /*json=*/true ); }

}   // namespace rw

