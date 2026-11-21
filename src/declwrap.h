// declwrap.h — WHERE A DECLARATION STARTS, wrapper prefix included (gate test/wrapperprefixcheck.sh).
//
// A symbol's span starts at the node its tags query captures, and several grammars put the start of the declaration
// OUTSIDE that node: an outer node wraps it (`export function f`, `@cache def f`, `template<typename T> T f`,
// `extern "C" int f`, Lua `local f = function`, Ruby `private def f`), or its attributes sit in front of it as
// siblings (Rust `#[inline] fn f`, a TS method's `@Input()`, a Dart or GDScript annotation). Symbol::sigStartByte is
// that inner start and STAYS it: the resolver, the quality lenses and the dead-code hedges read the text at it
// (resolve.h tests the keyword there, quality.h pythonDefIsDecorated scans upward from it, 70-odd files slice
// [sigStartByte, endByte)). Moving it would change every one of them and every signature row.
//
// What moves is the BODY A READER IS HANDED. A Python body without its decorator is a different function and a C++
// template body without `template<...>` does not compile, so packBodies / estimateExpandBodyTokens (the one seam every
// body verb goes through), the MCP fetch and the edit verbs (which splice the span --expand prints) start at
// declStartByte below. l= on a row is untouched: it was always the line of the NAME.
//
// The start is found by re-parsing the file the body is cut from, at answer time, with the grammar ingest used
// (ingest_declwrap.h, a section of ingest.cpp: this header stays tree-sitter-free, as serialize.h is). No stored field,
// no cache or parser-version change. When the re-parse finds no node that starts at the symbol's own start — a
// member-macro-blanked C++ parse, an embedded unit, a file edited since the index was built — the answer is the
// symbol's own start: the body as it was before, never a guessed prefix.
#pragma once

#include "model.h"

#include <cstdint>
#include <string_view>

namespace rw
{

// The first byte of the declaration whose captured node spans [defStart, defEnd) in `src`: the outermost wrapper
// around it, then the attribute run in front of that. Returns defStart when there is none, and when it cannot tell.
std::uint32_t wrappedDeclStart( std::string_view path, std::string_view src, std::uint32_t defStart, std::uint32_t defEnd );

// The same for a symbol, over the file text its body is cut from. `src` must be that FILE's bytes (not an extracted
// doc unit's: a caller holding one keeps sigStartByte).
inline std::size_t declStartByte( const IngestResult& ing, const Symbol& s, std::string_view src )
{
    if( s.fileId >= ing.files.size() || s.sigStartByte >= s.endByte || s.endByte > src.size() || !isCodeLang( s.lang ) )
    {
        return s.sigStartByte;
    }
    return wrappedDeclStart( ing.files[ s.fileId ], src, s.sigStartByte, s.endByte );
}

}   // namespace rw
