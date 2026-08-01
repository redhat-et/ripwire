#pragma once

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

#include "model.h"
#include "serialize.h"   // escapeXml, symTag, refRoleTag

#include <cstdio>
#include <string>
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
        if( c == ',' ) std::fputs( "&#44;", out );
        else           std::fputc( c, out );
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
    outUniqueFiles.clear();
    outRowPathIdx.clear();
    outRowPathIdx.reserve( rowFileIds.size() );
    // small-N first-seen scan (a flat-list verb's file count is modest); a HashMap would out-cost the scan.
    for( std::uint32_t fid : rowFileIds )
    {
        std::uint32_t idx = 0;
        bool          found = false;
        for( ; idx < outUniqueFiles.size(); ++idx ) if( outUniqueFiles[idx] == fid ) { found = true; break; }
        if( !found ) { idx = std::uint32_t( outUniqueFiles.size() ); outUniqueFiles.push_back( fid ); }
        outRowPathIdx.push_back( idx );
    }
}

// emit the <paths> table (index=path, space-separated), XML-escaped.
inline void emitPathTable( std::FILE* out, const IngestResult& ing,
                           const std::vector<std::uint32_t>& uniqueFiles, std::vector<char>& esc )
{
    std::fputs( "<paths>", out );
    for( std::size_t i = 0; i < uniqueFiles.size(); ++i )
    {
        if( i ) std::fputc( ' ', out );
        std::fprintf( out, "%zu=", i );
        const std::string_view p = escapeXml( ing.files[ uniqueFiles[i] ], esc );
        std::fwrite( p.data(), 1, p.size(), out );
    }
    std::fputs( "</paths>", out );
}

// COLUMNAR form of a symbol-row verb (--callers/--callees/--impact/--pr-context symbols). `wrapperTag` is the
// element name ("callers"), `wrapperAttrs` the already-formatted attribute string ("of=\"X\" count=\"17\"").
// `rows` are the symbol node ids in the caller's already-sorted order. Emits:
//   <TAG ATTRS format="columnar"><paths>..</paths><cols n= fields="path,name,line,kind">
//     <path>0,0,1,..</path><name>a,b,..</name><line>12,..</line><kind>fn,..</kind></cols></TAG>
inline void emitColumnarSymbolRows( std::FILE* out, const IngestResult& ing,
                                    const char* wrapperTag, const std::string& wrapperAttrs,
                                    const std::vector<NodeId>& rows )
{
    std::vector<char> esc;

    std::vector<std::uint32_t> rowFiles;  rowFiles.reserve( rows.size() );
    for( NodeId id : rows ) rowFiles.push_back( ing.symbols[id].fileId );
    std::vector<std::uint32_t> uniqueFiles, rowPathIdx;
    buildPathTable( rowFiles, uniqueFiles, rowPathIdx );

    std::fputs( kColumnarLegend, out );   // §B1.5: once per output, before the element it describes
    std::fprintf( out, "<%s %s format=\"columnar\">", wrapperTag, wrapperAttrs.c_str() );
    emitPathTable( out, ing, uniqueFiles, esc );
    std::fprintf( out, "<cols n=\"%zu\" fields=\"path,name,line,kind\">", rows.size() );

    // path index array
    std::fputs( "<path>", out );
    for( std::size_t i = 0; i < rowPathIdx.size(); ++i ) { if( i ) std::fputc( ',', out ); std::fprintf( out, "%u", rowPathIdx[i] ); }
    std::fputs( "</path>", out );
    // name array (XML-escaped; most identifiers never contain a comma, but markdown SECTION symbols and
    // canonical ids CAN (A4-F15) — writeCommaEscaped protects the ',' field separator from a value comma).
    std::fputs( "<name>", out );
    for( std::size_t i = 0; i < rows.size(); ++i )
    { if( i ) std::fputc( ',', out ); const std::string_view n = escapeXml( ing.symbols[ rows[i] ].name, esc ); writeCommaEscaped( out, n ); }
    std::fputs( "</name>", out );
    // line array
    std::fputs( "<line>", out );
    for( std::size_t i = 0; i < rows.size(); ++i ) { if( i ) std::fputc( ',', out ); std::fprintf( out, "%u", ing.symbols[ rows[i] ].line ); }
    std::fputs( "</line>", out );
    // kind array (terse tags)
    std::fputs( "<kind>", out );
    for( std::size_t i = 0; i < rows.size(); ++i ) { if( i ) std::fputc( ',', out ); std::fputs( symTag( ing.symbols[ rows[i] ].kind ), out ); }
    std::fputs( "</kind>", out );

    std::fprintf( out, "</cols></%s>", wrapperTag );
}

// COLUMNAR form of the --uses verb: use-site rows carry (fileId, line, role, enclosing-symbol name `in`)
// instead of a symbol kind. Same path-table + parallel-array shape; the `in` array uses ',' separators and
// an empty entry for file-scope sites (no enclosing symbol).
inline void emitColumnarUseSites( std::FILE* out, const IngestResult& ing,
                                  const std::string& wrapperAttrs,
                                  const std::vector<std::uint32_t>& fileIds,
                                  const std::vector<std::uint32_t>& lines,
                                  const std::vector<RefRole>&       roles,
                                  const std::vector<std::string>&   inNames )
{
    std::vector<char> esc;
    std::vector<std::uint32_t> uniqueFiles, rowPathIdx;
    buildPathTable( fileIds, uniqueFiles, rowPathIdx );
    const std::size_t nRows = fileIds.size();

    std::fputs( kColumnarLegend, out );   // §B1.5: the same one legend the symbol-row emitter uses
    std::fprintf( out, "<uses %s format=\"columnar\">", wrapperAttrs.c_str() );
    emitPathTable( out, ing, uniqueFiles, esc );
    std::fprintf( out, "<cols n=\"%zu\" fields=\"path,line,role,in_id\">", nRows );

    std::fputs( "<path>", out );
    for( std::size_t i = 0; i < rowPathIdx.size(); ++i ) { if( i ) std::fputc( ',', out ); std::fprintf( out, "%u", rowPathIdx[i] ); }
    std::fputs( "</path>", out );
    std::fputs( "<line>", out );
    for( std::size_t i = 0; i < nRows; ++i ) { if( i ) std::fputc( ',', out ); std::fprintf( out, "%u", lines[i] ); }
    std::fputs( "</line>", out );
    std::fputs( "<role>", out );
    for( std::size_t i = 0; i < nRows; ++i ) { if( i ) std::fputc( ',', out ); std::fputs( refRoleTag( roles[i] ), out ); }
    std::fputs( "</role>", out );
    std::fputs( "<in_id>", out );
    for( std::size_t i = 0; i < nRows; ++i )
    { if( i ) std::fputc( ',', out ); const std::string_view v = escapeXml( inNames[i], esc ); writeCommaEscaped( out, v ); }
    std::fputs( "</in_id>", out );

    std::fputs( "</cols></uses>", out );
}

}   // namespace rw
