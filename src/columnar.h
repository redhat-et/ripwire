#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings


// columnar.h — an OPT-IN columnar re-serialization for the FLAT list verbs
// (--callers / --callees / --uses / --impact). §A5c: this header and --help both used to name the
// --pr-context changed-symbols rows too; prcontext.h has never contained a line of columnar code, so the
// claim was struck from both rather than implemented, and cli.h's guard now refuses the combination.
// The default XML
// form pays ~69% structural overhead on these: per-row tag markup (`<s t= n= p= />`) repeated once per row,
// plus the same file PATH repeated on every row. The columnar form emits the path ONCE in a <paths> table
// (integer refs) and the per-field data as PARALLEL ARRAYS, so the markup is amortized across all rows.
//
// SCOPE GUARD (from the literature): columnar/TOON collapses to 0% accuracy on NESTED data, so
// this is applied ONLY to the genuinely TABULAR list verbs — NEVER the nested symbol/edge map. The default
// stays minified XML (byte-identical, G4 gate intact); columnar is reached only under --format=columnar.
//
// The columnar block is still VALID XML (so xmllint/G4 holds): a <paths> table element, then a <cols>
// element whose children are one array element per field, each carrying comma-joined, XML-escaped values.
// A consumer round-trips it by zipping the arrays against the path table — same symbol set, re-encoded.

#include "memberowner.h"   // MemberOwners / qualifiedMemberName — the name column spells a member as the XML row does
#include "model.h"
#include "serialize.h"   // escapeXml, symTag, refRoleTag
#include "graph.h"       // isTestedByReach — the tested column reads the test-reach lens (card A6)

#include <algorithm>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// A4-F15 fix: the ',' field separator mis-zips a whole parallel-array row (and every row after it) when an
// emitted value itself contains a literal comma — a markdown SECTION symbol named e.g. "# results,
// discussion", or a canonical id embedding a comma-bearing path, shifts every subsequent field by one with
// no parse error to flag it (silent corruption, not a crash). Escape ',' -> the numeric XML character
// reference '&#44;': it round-trips through ordinary XML-entity decoding for free (a consumer un-escapes
// it the same way it un-escapes '&amp;'/'&lt;'), and escapeXml() never emits a bare ',' itself so this
// composes safely on top of the existing XML escaping. One shared helper, applied at every FREE-TEXT
// value-emission point in this file (the name array and the `in_id` array — the only two columns whose
// content is not a closed, comma-free vocabulary like a path index, line number, kind tag, or role tag).
inline void writeCommaEscaped( std::FILE* out, std::string_view alreadyXmlEscaped )
{
    for( char c : alreadyXmlEscaped )
    {
        if( c == ',' )
        {
            std::fputs( "&#44;", out );
        }
        else
        {
            std::fputc( c, out );
        }
    }
}

// §B1.5 — THE COLUMNAR LEGEND. Every columnar-capable verb ships its own XML row legend describing
// `p=file:line` / `t=` / `n=` ATTRIBUTES, and in this form none of those attributes exist: the reader was
// handed a description of a shape the output does not have, while the contract it DOES have (the path table,
// the parallel-array zip, the n= alignment rule, the empty-page shape and the `&#44;` value escape) lived only
// in the source comments of this file. Emitted ONCE per output by the two emitters below, so all four verbs
// (--callers/--callees/--uses/--impact) are served by one string and cannot drift into four descriptions.
// Kept terse on purpose: this is the token-economy form, so the legend is a fixed cost on every result.
// §B7.9 (CA4): the sentence used to say "the legend above describes", which is a FORWARD REFERENCE to a
// document that does not always exist — on --callers and --callees this string is the first bytes of the
// output, so it pointed a reader at nothing. Only --uses and --impact ship a row legend ahead of it. Restated
// as a fact about the XML row FORM (which every one of the four has), so it reads true in both positions.
inline constexpr const char* kColumnarLegend =
    "<!-- format=columnar: PARALLEL ARRAYS, not per-row attributes — the t=/n=/p= attributes this verb's XML row "
    "form carries are NOT emitted in this form. Zip by index: <paths> maps `I=path`; each array under <cols> holds "
    "exactly n= comma-separated values in ONE shared row order, and the path column is an index into <paths>. "
    "fields= names the columns, in array order. n=\"0\" (an empty page) means every array is present and empty. "
    "A ',' inside a VALUE is escaped as &#44; (ordinary XML entity decoding restores it), so splitting a row "
    "array on ',' can never mis-zip. -->";

// build the deduplicated path table for a set of fileIds, in FIRST-SEEN order (deterministic — the caller
// passes rows already in its sorted order). Returns {ordered unique fileIds, per-row path-index}.
inline void buildPathTable( const std::vector<std::uint32_t>& rowFileIds,
                            std::vector<std::uint32_t>& outUniqueFiles, std::vector<std::uint32_t>& outRowPathIdx )
{
    ASSUME_NO_ALIAS3( rowFileIds, outUniqueFiles, outRowPathIdx );
    outUniqueFiles.clear();
    outRowPathIdx.clear();
    outRowPathIdx.reserve( rowFileIds.size() );
    // small-N first-seen scan (a flat-list verb's file count is modest); a HashMap would out-cost the scan.
    for( std::uint32_t fid : rowFileIds )
    {
        std::uint32_t idx = 0;
        bool          found = false;
        for( ; idx < outUniqueFiles.size(); ++idx )
        {
            if( outUniqueFiles[idx] == fid )
            {
                found = true;
                break;
            }
        }
        if( !found ) { idx = std::uint32_t( outUniqueFiles.size() ); outUniqueFiles.push_back( fid ); }
        outRowPathIdx.push_back( idx );
    }
}

// emit the <paths> table (index=path, space-separated), XML-escaped. `rootPrefix` empty ⇒ paths stay the
// ing.files[] spelling unchanged (multi-root, or a caller with no single root to strip) — R-E (2026-08-17
// harvest): the table already de-duplicates each path to ONE entry, but that one entry was still absolute
// on an absolute-root run, so the fix applies here too, same helper serialize()'s pathRel uses.
inline void emitPathTable( std::FILE* out, const IngestResult& ing,
                           const std::vector<std::uint32_t>& uniqueFiles, std::vector<char>& esc,
                           std::string_view rootPrefix = {} )
{
    std::fputs( "<paths>", out );
    for( std::size_t i = 0; i < uniqueFiles.size(); ++i )
    {
        if( i )
        {
            std::fputc( ' ', out );
        }
        rw::emitTo( out, "{}=", i );
        const std::string_view raw = ing.files[ uniqueFiles[i] ];
        const std::string_view rel = rootPrefix.empty() ? raw : rw::sarif::rootRelativeUri( raw, rootPrefix );
        const std::string_view p   = escapeXml( rel, esc );
        std::fwrite( p.data(), 1, p.size(), out );
    }
    std::fputs( "</paths>", out );
}

// A dense 0/1 column `<TAG>1,0,..</TAG>`, one value per row in row order: `flagAt( i )` is row i's flag.
template <class FlagAt>
inline void emitColumnarFlagColumn( std::FILE* out, std::string_view tag, std::size_t rowCount, FlagAt&& flagAt )
{
    rw::emitTo( out, "<{}>", tag );
    for( std::size_t i = 0; i < rowCount; ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        std::fputc( flagAt( i ) ? '1' : '0', out );
    }
    rw::emitTo( out, "</{}>", tag );
}

// A6: the optional dense 0/1 `<tested>` column, split out of emitColumnarSymbolRows so that function's own
// branch count does not grow for a column three of its four callers never ask for.
inline void emitColumnarTestedColumn( std::FILE* out, const IngestResult& ing, const std::vector<NodeId>& rows,
                                      const std::vector<char>& testReach )
{
    emitColumnarFlagColumn( out, "tested", rows.size(), [ & ]( std::size_t i ) { return isTestedByReach( ing, testReach, rows[i] ); } );
}

// 0.6.5: the optional dense `<depth>` column — --impact's hop depth per row (graph.h transitiveCallersDepth), one value
// per row in row order. Built as one string and written once: a depth is a multi-digit number, not the tested column's
// single character.
inline void emitColumnarDepthColumn( std::FILE* out, const std::vector<NodeId>& rows, const std::vector<std::uint32_t>& depth )
{
    std::string column = "<depth>";
    for( NodeId n : rows )
    {
        column += std::to_string( depth[n] );
        column += ',';
    }
    if( !rows.empty() )
    {
        column.pop_back();   // the separator after the last value
    }
    column += "</depth>";
    rw::emitTo( out, "{}", column );
}

// The optional dense `<via>` column — 1 where the row's edge is name-only (via="name"), 2 where it is a direct markdown
// link (via="link"), one value per row in row order. Present only when some row carries it, so an answer with no such
// row pays 0 bytes; columnarViaField is its fields= suffix.
inline bool columnarViaPresent( const std::vector<char>* viaName ) noexcept
{
    return viaName != nullptr && std::any_of( viaName->begin(), viaName->end(), []( char c ) { return c != 0; } );
}
inline std::string_view columnarViaField( const std::vector<char>* viaName ) noexcept
{
    return columnarViaPresent( viaName ) ? ",via" : "";
}
inline void emitColumnarViaColumn( std::FILE* out, const std::vector<char>& via, std::size_t rowCount )
{
    rw::emitTo( out, "<via>" );
    for( std::size_t i = 0; i < rowCount; ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        const unsigned char v = ( i < via.size() ) ? static_cast<unsigned char>( via[ i ] ) : 0;
        std::fputc( v <= 9 ? char( '0' + v ) : '0', out );
    }
    rw::emitTo( out, "</via>" );
}

// CALLSITE-AT (2026-10-09): the optional `<sites_at>` column — each row's call sites (editcheck.h rowCallSites), its tokens joined
// by a space, XML-escaped with a value comma written &#44; (kColumnarLegend's rule), an empty value for a row with none —
// and the dense `<sites_total>` column (the uncut count per row) only when some row's list was cut. Present only when the
// caller passed sites, so every other columnar answer is byte-identical. `totals` is parallel to `tokens`.
inline bool columnarAtCut( const std::vector<std::vector<std::string>>& tokens, const std::vector<std::size_t>& totals ) noexcept
{
    for( std::size_t i = 0; i < tokens.size() && i < totals.size(); ++i )
    {
        if( totals[i] > tokens[i].size() )
        {
            return true;
        }
    }
    return false;
}
inline void emitColumnarAtColumns( std::FILE* out, const std::vector<std::vector<std::string>>& tokens, const std::vector<std::size_t>& totals )
{
    EXPECTS( tokens.size() == totals.size(), "one total per row" );
    std::vector<char> esc;
    std::fputs( "<sites_at>", out );
    for( std::size_t i = 0; i < tokens.size(); ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        for( std::size_t k = 0; k < tokens[i].size(); ++k )
        {
            if( k )
            {
                std::fputc( ' ', out );
            }
            writeCommaEscaped( out, escapeXml( tokens[i][k], esc ) );
        }
    }
    std::fputs( "</sites_at>", out );
    if( columnarAtCut( tokens, totals ) )
    {
        std::string column = "<sites_total>";
        for( std::size_t i = 0; i < totals.size(); ++i )
        {
            column += i ? "," : "";
            column += std::to_string( totals[i] );
        }
        column += "</sites_total>";
        rw::emitTo( out, "{}", column );
    }
}

// The per-row extras a caller may add after the core columns, in ONE argument so the row emitter's signature does not grow per
// column: FE-B's via flags and CALLSITE-AT's sites (tokens + parallel totals). Value-initialized = none of them.
// attrib-multidef (defattrib.h): `ofDef` is each row's of_def tokens (space-separated, a multi-group answer only), `defRows` the
// <def> table printed before <cols>, `splitArm` the dense 0/1 `<split>` column (a one-group answer's prov="split" rows, present
// only when some row carries it — columnarViaPresent's rule).
struct ColumnarRowExtras
{
    const std::vector<char>*                     viaName;
    const std::vector<std::vector<std::string>>* atTokens;
    const std::vector<std::size_t>*              atTotals;
    const std::vector<std::string>*              ofDef    = nullptr;
    const std::string*                           defRows  = nullptr;
    const std::vector<char>*                     splitArm = nullptr;
    const std::string*                           tailRows = nullptr;   // XML rows kept verbatim after </cols> (lane declined-sites: <dc>)
    const std::vector<char>*                     byType   = nullptr;   // L7 --impact: the dense 0/1 `<by_type>` column (reached only through a type mention), present-only
};
inline std::string columnarExtraFields( const ColumnarRowExtras& extras )
{
    std::string fields( columnarViaField( extras.viaName ) );
    if( extras.atTokens != nullptr && extras.atTotals != nullptr )
    {
        fields += columnarAtCut( *extras.atTokens, *extras.atTotals ) ? ",sites_at,sites_total" : ",sites_at";
    }
    fields += extras.ofDef != nullptr ? ",of_def" : "";
    fields += columnarViaPresent( extras.splitArm ) ? ",split" : "";
    fields += columnarViaPresent( extras.byType ) ? ",by_type" : "";
    return fields;
}
// the of_def column: each row's tokens, comma-separated rows (a token holds no comma)
inline void emitColumnarOfDefColumn( std::FILE* out, const std::vector<std::string>& ofDef )
{
    std::string column = "<of_def>";
    for( std::size_t i = 0; i < ofDef.size(); ++i )
    {
        column += i ? "," : "";
        column += ofDef[i];
    }
    column += "</of_def>";
    rw::emitTo( out, "{}", column );
}

// The optional columns a caller asked for, and the fields= suffix naming them, in ONE place: emitColumnarSymbolRows
// reads each through these, so its own branch count does not grow per optional column.
inline std::string_view columnarOptionalFields( bool hasTested, bool hasDepth ) noexcept
{
    return hasTested ? ( hasDepth ? ",tested,depth" : ",tested" ) : ( hasDepth ? ",depth" : "" );
}
inline void emitColumnarOptionalColumns( std::FILE* out, const IngestResult& ing, const std::vector<NodeId>& rows,
                                         const std::vector<char>* testReach, const std::vector<std::uint32_t>* depth,
                                         const ColumnarRowExtras& extras )
{
    const std::vector<char>* viaName = extras.viaName;
    if( testReach )
    {
        emitColumnarTestedColumn( out, ing, rows, *testReach );
    }
    if( depth )
    {
        emitColumnarDepthColumn( out, rows, *depth );
    }
    if( columnarViaPresent( viaName ) )
    {
        emitColumnarViaColumn( out, *viaName, rows.size() );
    }
    if( extras.atTokens != nullptr && extras.atTotals != nullptr )
    {
        emitColumnarAtColumns( out, *extras.atTokens, *extras.atTotals );
    }
    if( extras.ofDef != nullptr )
    {
        emitColumnarOfDefColumn( out, *extras.ofDef );
    }
    if( columnarViaPresent( extras.splitArm ) )
    {
        emitColumnarFlagColumn( out, "split", rows.size(), [ & ]( std::size_t i ) { return i < extras.splitArm->size() && ( *extras.splitArm )[ i ] != 0; } );
    }
    if( columnarViaPresent( extras.byType ) )
    {
        emitColumnarFlagColumn( out, "by_type", rows.size(), [ & ]( std::size_t i ) { return i < extras.byType->size() && ( *extras.byType )[ i ] != 0; } );
    }
}

// The `<name>` column: XML-escaped names (most identifiers never contain a comma, but markdown SECTION symbols and canonical ids
// CAN (A4-F15) — writeCommaEscaped protects the ',' field separator from a value comma).
// QUALNAME-1: a member row spells `Owner.name` exactly as its XML twin's n= does (memberowner.h); the owner table is built only when a row
// can be a member, so a free-function page pays nothing. (columnarcheck's round-trip arm compares the two forms' (name, line) sets.)
inline void emitNameColumn( std::FILE* out, const IngestResult& ing, const std::vector<NodeId>& rows, std::vector<char>& esc )
{
    const bool                        anyMember = std::ranges::any_of( rows, [ & ]( NodeId id ) { return memberOwnerPossible( ing.symbols[id] ); } );
    const std::optional<MemberOwners> owners    = anyMember ? std::optional<MemberOwners>( std::in_place, ing ) : std::nullopt;
    std::fputs( "<name>", out );
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        const Symbol&          sym   = ing.symbols[rows[i]];
        const std::string      named = owners ? qualifiedMemberName( *owners, sym ) : sym.name;
        const std::string_view n     = escapeXml( named, esc );
        writeCommaEscaped( out, n );
    }
    std::fputs( "</name>", out );
}

// COLUMNAR form of a symbol-row verb (--callers/--callees/--impact/--pr-context symbols). `wrapperTag` is the
// element name ("callers"), `wrapperAttrs` the already-formatted attribute string ("of=\"X\" count=\"17\"").
// `rows` are the symbol node ids in the caller's already-sorted order. Emits:
//   <TAG ATTRS format="columnar"><paths>..</paths><cols n= fields="path,name,line,kind">
//     <path>0,0,1,..</path><name>a,b,..</name><line>12,..</line><kind>fn,..</kind></cols></TAG>
// A6: `testReach` is optional — when given, "tested" joins fields= and a fifth dense `<tested>0,1,..</tested>`
// column rides alongside (a parallel array cannot omit a false entry the way an XML attribute can; the
// column itself is present only when a caller passed the lens, so a caller with no test data pays 0 bytes).
// 0.6.5: `depth` (optional, --impact only) adds a dense `<depth>` column — transitiveCallersDepth's hop per row — and
// names it in fields=; a caller that passes none pays 0 bytes, like the tested column.
// FE-B / CALLSITE-AT: `extras` (ColumnarRowExtras, value-initialized = none) adds the dense `<via>` column (columnarViaPresent)
// when a row is hedged, and the `<sites_at>` (+ `<sites_total>` when cut) columns when the caller passed sites.
inline void emitColumnarSymbolRows( std::FILE* out, const IngestResult& ing,
                                    const char* wrapperTag, const std::string& wrapperAttrs,
                                    const std::vector<NodeId>& rows, std::string_view rootPrefix = {},
                                    const std::vector<char>* testReach = nullptr,
                                    const std::vector<std::uint32_t>* depth = nullptr,
                                    const ColumnarRowExtras& extras = {} )
{
    std::vector<char> esc;

    std::vector<std::uint32_t> rowFiles;  rowFiles.reserve( rows.size() );
    for( NodeId id : rows )
    {
        rowFiles.push_back( ing.symbols[id].fileId );
    }
    std::vector<std::uint32_t> uniqueFiles, rowPathIdx;
    buildPathTable( rowFiles, uniqueFiles, rowPathIdx );

    std::fputs( kColumnarLegend, out );   // §B1.5: once per output, before the element it describes
    rw::emitTo( out, "<{} {} format=\"columnar\">", wrapperTag, wrapperAttrs.c_str() );
    emitPathTable( out, ing, uniqueFiles, esc, rootPrefix );
    if( extras.defRows != nullptr )
    {
        rw::emitRaw( out, extras.defRows->c_str() );   // attrib-multidef: the <def> table the of_def column's ix= name
    }
    rw::emitTo( out, "<cols n=\"{}\" fields=\"path,name,line,kind{}{}\">", rows.size(), columnarOptionalFields( testReach != nullptr, depth != nullptr ),
                columnarExtraFields( extras ) );

    // path index array
    std::fputs( "<path>", out );
    for( std::size_t i = 0; i < rowPathIdx.size(); ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        rw::emitTo( out, "{}", rowPathIdx[i] );
    }
    std::fputs( "</path>", out );
    emitNameColumn( out, ing, rows, esc );
    // line array
    std::fputs( "<line>", out );
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        rw::emitTo( out, "{}", ing.symbols[rows[i]].line );
    }
    std::fputs( "</line>", out );
    // kind array (terse tags)
    std::fputs( "<kind>", out );
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        std::fputs( symTag( ing.symbols[rows[i]].kind ), out );
    }
    std::fputs( "</kind>", out );
    // A6 / 0.6.5 / FE-B: each present only when the caller passed it — see the wrapper banner and emitColumnarOptionalColumns.
    emitColumnarOptionalColumns( out, ing, rows, testReach, depth, extras );

    rw::emitTo( out, "</cols>{}</{}>", extras.tailRows != nullptr ? std::string_view( *extras.tailRows ) : std::string_view(), wrapperTag );
}

// COLUMNAR form of the --uses verb: use-site rows carry (fileId, line, role, enclosing-symbol name `in`)
// instead of a symbol kind. Same path-table + parallel-array shape; the `in` array uses ',' separators and
// an empty entry for file-scope sites (no enclosing symbol).
inline void emitColumnarUseSites( std::FILE* out, const IngestResult& ing,
                                  const std::string& wrapperAttrs,
                                  const std::vector<std::uint32_t>& fileIds,
                                  const std::vector<std::uint32_t>& lines,
                                  const std::vector<RefRole>&       roles,
                                  const std::vector<std::string>&   inNames,
                                  std::string_view rootPrefix = {} )
{
    std::vector<char> esc;
    std::vector<std::uint32_t> uniqueFiles, rowPathIdx;
    buildPathTable( fileIds, uniqueFiles, rowPathIdx );
    const std::size_t nRows = fileIds.size();

    std::fputs( kColumnarLegend, out );   // §B1.5: the same one legend the symbol-row emitter uses
    rw::emitTo( out, "<uses {} format=\"columnar\">", wrapperAttrs.c_str() );
    emitPathTable( out, ing, uniqueFiles, esc, rootPrefix );
    rw::emitTo( out, "<cols n=\"{}\" fields=\"path,line,role,in_id\">", nRows );

    std::fputs( "<path>", out );
    for( std::size_t i = 0; i < rowPathIdx.size(); ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        rw::emitTo( out, "{}", rowPathIdx[i] );
    }
    std::fputs( "</path>", out );
    std::fputs( "<line>", out );
    for( std::size_t i = 0; i < nRows; ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        rw::emitTo( out, "{}", lines[i] );
    }
    std::fputs( "</line>", out );
    std::fputs( "<role>", out );
    for( std::size_t i = 0; i < nRows; ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        std::fputs( refRoleTag( roles[i] ), out );
    }
    std::fputs( "</role>", out );
    std::fputs( "<in_id>", out );
    for( std::size_t i = 0; i < nRows; ++i )
    {
        if( i )
        {
            std::fputc( ',', out );
        }
        const std::string_view v = escapeXml( inNames[i], esc );
        writeCommaEscaped( out, v );
    }
    std::fputs( "</in_id>", out );

    std::fputs( "</cols></uses>", out );
}

}   // namespace rw
