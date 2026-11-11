#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings


// degradedscan.h — THE ONE degraded-parse text scan behind every "that name resolved to nothing" refusal.
//
// WHY THIS FILE EXISTS (degradedhintcheck, 2026-08-30). The health pass records which indexed files'
// parses hold ERROR/MISSING nodes, and --skipped discloses them — but a refusal never routed the reader
// there, so a symbol sitting in a shredded file (the looksObjC misroute: src/ingest_model.h, err=190)
// answered a bare "symbol not found" and sent an agent hunting for a rename that never happened. The fix
// is a scan of the BYTES of the parse-degraded files for the missing name as a WHOLE WORD — precise by
// construction: an ordinary typo occurs in no file, so it never fires on misspellings (this repo carries
// 65 deliberately-degraded fixtures; a blanket "there are degraded files" note would ride on every
// refusal).
//
// The scan landed inside the CLI's selectorrefuse.h first; the MCP arms refuse in their own vocabulary
// (mcprefusal.h) and needed the SAME facts under different wording — and a byte-scan that exists twice is
// two budgets, two boundary predicates and two behaviours. So the scan lives here, returning FACTS, and
// each surface words them: selectorrefuse.h's degradedParseClause (CLI, parenthetical, --skipped retry)
// and mcprefusal.h's degradedParseNote (MCP, sentence, grep-verb retry). Same split as didyoumean.h, the
// other enrichment both refusal surfaces already share.
//
// Cold path only (the command is already failing), and bounded: at most kDegradedScanFiles files and
// kDegradedScanBytes total are read; readWhole itself refuses oversized files. A budget hit or unreadable
// file just means no hit — an ABSENT note claims nothing, same as the near-miss suggester. First matching
// file only: --skipped is the itemization, this is the routing.

#include "model.h"
#include "darkflags.h"      // readWhole / wholeWordAt — the shared lexical helpers (no second copy)
#include "crossref.h"       // definesNameAt / definitionShaped — whereis' lexical definition reading (lexicalDefHit)
#include "lintrules.h"      // langOfPath — which clean files ride the C++ parse path (object-like #define not indexed)
#include "langfacts.h"      // LangFacts::objectMacrosUnindexed

#include <algorithm>
#include <cstdint>
#include <optional>

#include <cstddef>
#include <cstdio>
#include <string>
#include <string_view>

namespace rw
{

inline constexpr std::size_t kDegradedScanFiles = 32;
inline constexpr std::size_t kDegradedScanBytes = 8u << 20;

// The facts a wording surface needs, and nothing pre-worded: WHICH indexed file textually holds the name,
// and how much of that file's parse is error bytes. errRatio is formatted ONCE ("%.3f") so the two
// surfaces can never print different digits for the same file.
struct DegradedTextHit
{
    bool        found     = false;
    std::size_t fileIndex = 0;         // into ing.files, valid only when found
    char        errRatio[ 16 ] = {};   // "%.3f"; <= 1.000 by construction (errBytes <= fileBytes)
};

inline DegradedTextHit degradedTextHit( const IngestResult& ing, std::string_view name )
{
    if( name.empty() || name.size() > 256 )
    {
        return {};
    }
    std::size_t scannedFiles = 0, scannedBytes = 0;
    for( std::size_t fileIndex = 0; fileIndex < ing.files.size() && fileIndex < ing.fileHealth.size(); ++fileIndex )
    {
        if( !fileParseDegraded( ing, fileIndex ) )
        {
            continue;                                    // clean, or the ingest never parsed it — not this scan's claim
        }
        const FileHealth& h = ing.fileHealth[ fileIndex ];
        if( ++scannedFiles > kDegradedScanFiles || ( scannedBytes += h.fileBytes ) > kDegradedScanBytes )
        {
            return {};                                   // budget — absent claims nothing
        }
        const std::optional<std::string> bytes = darkflags::readWhole( diskPath( ing, std::uint32_t( fileIndex ) ) );
        if( !bytes )
        {
            continue;
        }
        const std::string_view hay( *bytes );
        for( std::size_t at = hay.find( name ); at != std::string_view::npos; at = hay.find( name, at + 1 ) )
        {
            if( darkflags::wholeWordAt( hay, at, name.size() ) )
            {
                DegradedTextHit hit;
                hit.found     = true;
                hit.fileIndex = fileIndex;
                rw::formatTo( hit.errRatio, sizeof( hit.errRatio ), "{:.3f}", double( h.errBytes ) / double( h.fileBytes ) );
                return hit;
            }
        }
    }
    return {};
}

// ── LEXICAL-DEF (B31: USES-UNARMED-DISCLOSE + TMUX-STRUCT-WINDOW) ─────────────────────────────────────────────────
//
// The textual hit above names the FIRST degraded file that mentions the name, in path order, and stops at 32 files.
// That was the wrong file twice on tmux: `--defs=window` named alerts.c (a mention) while `struct window {` sits at
// tmux.h:1441 (the 108th degraded file, past the cap), and `--defs=TMUX_SOCK` said only "did you mean 'tmuxproc'"
// for a name tmux.h:95 `#define`s — object-like macros are deliberately not captured on the C++ path
// (queries/cpp/tags.scm), so "not found" there is a floor the refusal never named. This scan answers the sharper
// question: where do the BYTES define the name the index does not hold? Two readings, one walk:
//   * a parse-DEGRADED file: a line definitionShaped() reads as a definition (whereis' own lexical label, so the two
//     verbs name the same site);
//   * a clean C++-path file (.h/.hpp/.cpp/.mm …, langOfPath Cpp/ObjC): only an object-like `#define NAME`, the one
//     definition shape that path never indexes. A clean file's other lexical "definitions" stay unclaimed: its parse is
//     the better evidence.
// The first such line in path order wins. Bounded like the scan above (cold path: the command is already failing),
// with a wider file cap because the def is the point; a budget hit returns what was found so far, never a guess.
inline constexpr std::size_t kLexicalDefScanFiles = 4096;
inline constexpr std::size_t kLexicalDefScanBytes = 16u << 20;

struct LexicalDefHit
{
    bool          found       = false;
    std::size_t   fileIndex   = 0;       // into ing.files, valid only when found
    std::uint32_t line        = 0;       // 1-based
    bool          objectMacro = false;   // `#define NAME` with no parameter list
    bool          degraded    = false;   // the file's parse is degraded; errRatio is then set
    char          errRatio[ 16 ] = {};
};

// `#define NAME` with NO parameter list: the byte after the name is not '('.
inline bool objectMacroAt( std::string_view line, std::size_t at, std::size_t nameLen ) noexcept
{
    return crossref::definesNameAt( line, at ) && ( at + nameLen >= line.size() || line[ at + nameLen ] != '(' );
}

// `struct NAME;` / `class NAME;`: a forward declaration reads definition-shaped to whereis' label but defines nothing.
inline bool forwardDeclarationAt( std::string_view line, std::size_t at, std::size_t nameLen ) noexcept
{
    std::string_view rest = line.substr( std::min( at + nameLen, line.size() ) );
    while( !rest.empty() && ( rest.front() == ' ' || rest.front() == '\t' ) )
    {
        rest.remove_prefix( 1 );
    }
    return rest.starts_with( ';' );
}

// The first line of `hay` whose first whole-word occurrence of `name` satisfies `accept( line, at )`; 0 when none.
template<class Accept>
inline std::uint32_t firstLineWhere( std::string_view hay, std::string_view name, Accept&& accept )
{
    std::uint32_t lineNo  = 1;
    std::size_t   counted = 0;
    for( std::size_t at = hay.find( name ); at != std::string_view::npos; )
    {
        lineNo += std::uint32_t( std::count( hay.begin() + std::ptrdiff_t( counted ), hay.begin() + std::ptrdiff_t( at ), '\n' ) );
        counted                     = at;
        const std::size_t nl        = hay.rfind( '\n', at );
        const std::size_t lineStart = nl == std::string_view::npos ? 0 : nl + 1;
        std::size_t       lineEnd   = hay.find( '\n', at );
        lineEnd                     = lineEnd == std::string_view::npos ? hay.size() : lineEnd;
        const std::string_view line = hay.substr( lineStart, lineEnd - lineStart );
        for( std::size_t inLine = line.find( name ); inLine != std::string_view::npos; inLine = line.find( name, inLine + 1 ) )
        {
            if( darkflags::wholeWordAt( line, inLine, name.size() ) )
            {
                if( accept( line, inLine ) )
                {
                    return lineNo;
                }
                break;   // one reading per line, whereis' rule: the line's first whole-word occurrence is its evidence
            }
        }
        at = lineEnd >= hay.size() ? std::string_view::npos : hay.find( name, lineEnd + 1 );
    }
    return 0;
}

inline LexicalDefHit lexicalDefHit( const IngestResult& ing, std::string_view name )
{
    if( name.empty() || name.size() > 256 )
    {
        return {};
    }
    std::size_t scannedFiles = 0, scannedBytes = 0;
    for( std::size_t fileIndex = 0; fileIndex < ing.files.size(); ++fileIndex )
    {
        const bool degraded = fileParseDegraded( ing, fileIndex );
        if( !degraded && !langFacts( langOfPath( ing.files[ fileIndex ] ) ).objectMacrosUnindexed )
        {
            continue;
        }
        const std::optional<std::string> bytes = darkflags::readWhole( diskPath( ing, std::uint32_t( fileIndex ) ) );
        if( !bytes )
        {
            continue;
        }
        if( ++scannedFiles > kLexicalDefScanFiles || ( scannedBytes += bytes->size() ) > kLexicalDefScanBytes )
        {
            return {};   // budget — absent claims nothing
        }
        bool                macro = false;
        const std::uint32_t line  = firstLineWhere( *bytes, name, [ & ]( std::string_view text, std::size_t at )
        {
            macro = objectMacroAt( text, at, name.size() );
            return macro || ( degraded && crossref::definitionShaped( text, name, at ) && !forwardDeclarationAt( text, at, name.size() ) );
        } );
        if( line != 0 )
        {
            LexicalDefHit hit;
            hit.found       = true;
            hit.fileIndex   = fileIndex;
            hit.line        = line;
            hit.objectMacro = macro;
            hit.degraded    = degraded;
            if( degraded )
            {
                const FileHealth& h = ing.fileHealth[ fileIndex ];
                rw::formatTo( hit.errRatio, sizeof( hit.errRatio ), "{:.3f}", double( h.errBytes ) / double( h.fileBytes ) );
            }
            return hit;
        }
    }
    return {};
}

}   // namespace rw
