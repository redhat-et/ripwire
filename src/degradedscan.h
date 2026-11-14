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

// THE one formatting of a degraded file's error ratio, for both hits below (each carries its own char[16]): two surfaces
// and two scans can never print different digits for the same file.
template<class Hit>
inline void setErrRatio( Hit& hit, const FileHealth& h )
{
    rw::formatTo( hit.errRatio, sizeof( hit.errRatio ), "{:.3f}", double( h.errBytes ) / double( h.fileBytes ) );
}

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
                setErrRatio( hit, h );
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
// with a wider file cap because the def is the point; a budget hit returns capped (nothing found in what was read), and
// both refusal renderers say the scan stopped, so a miss past the budget never reads as a finished scan.
inline constexpr std::size_t kLexicalDefScanFiles = 4096;
inline constexpr std::size_t kLexicalDefScanBytes = 16u << 20;

struct LexicalDefHit
{
    bool          found       = false;
    std::size_t   fileIndex   = 0;       // into ing.files, valid only when found
    std::uint32_t line        = 0;       // 1-based
    bool          objectMacro = false;   // `#define NAME` with no parameter list
    bool          degraded    = false;   // the file's parse is degraded; errRatio is then set
    bool          capped      = false;   // the scan stopped at its budget before reading every file (found is then false)
    char          errRatio[ 16 ] = {};
};

// Does byte `at` sit inside a C++ raw string literal `R"delim( … )delim"` (also u8R / uR / UR / LR)? A `#define GHOST` line
// inside one is text, not a macro (LEXDEF-RAWSTRING, CodeRabbit #630). One forward pass like BlockCommentState: `at` must not
// decrease; each raw string is located once. The forward pass skips `//` and `/* */` comments and ordinary string and character
// literals, so an `R"(` written inside one never opens a span that could swallow a real raw string's opener (CodeRabbit 4570578017).
class RawStringState
{
public:
    explicit RawStringState( std::string_view hay ) noexcept : hay_( hay ) { advance( 0 ); }

    bool insideAt( std::size_t at ) noexcept
    {
        DASSERT( at >= last_ );
        last_ = at;
        while( spanEnd_ <= at && spanStart_ != std::string_view::npos )
        {
            advance( spanEnd_ );
        }
        return spanStart_ != std::string_view::npos && spanStart_ < at && at < spanEnd_;
    }

private:
    // The first raw string opening at or after `from` (a code position: 0, or the end of the previous raw string): [spanStart_,
    // spanEnd_), the end at the hay's end when it never closes. One lexical pass over comments and literals, linear in the hay.
    void advance( std::size_t from ) noexcept
    {
        const std::size_t n = hay_.size();
        for( std::size_t i = from; i < n; )
        {
            const char c = hay_[ i ];
            if( c == '/' && i + 1 < n && ( hay_[ i + 1 ] == '/' || hay_[ i + 1 ] == '*' ) )
            {
                const std::size_t e = hay_[ i + 1 ] == '/' ? hay_.find( '\n', i + 2 ) : hay_.find( "*/", i + 2 );
                i                   = e == std::string_view::npos ? n : e + ( hay_[ i + 1 ] == '/' ? 1 : 2 );
                continue;
            }
            if( c == 'R' && i + 1 < n && hay_[ i + 1 ] == '"' && openAt( i ) )
            {
                return;
            }
            if( c == '"' || ( c == '\'' && !digitSeparatorAt( i ) ) )
            {
                std::size_t j = i + 1;   // an ordinary literal ends at its unescaped quote, or at the line's end
                while( j < n && hay_[ j ] != c && hay_[ j ] != '\n' )
                {
                    j += hay_[ j ] == '\\' ? 2 : 1;
                }
                i = j + 1;
                continue;
            }
            ++i;
        }
        spanStart_ = std::string_view::npos;
        spanEnd_   = std::string_view::npos;
    }

    // Is the `'` at `i` a digit separator (`1'000`, `0xFF'FF`)? It is when the identifier-byte run before it starts with a digit;
    // after a letter it is a character literal's opening quote (`'x'`, `L'x'`, `u8'x'`).
    bool digitSeparatorAt( std::size_t i ) const noexcept
    {
        std::size_t b = i;
        while( b > 0 && darkflags::identByte( (unsigned char)hay_[ b - 1 ] ) )
        {
            --b;
        }
        return b < i && hay_[ b ] >= '0' && hay_[ b ] <= '9';
    }

    // Is the `R"` at `o` (code, not a comment or literal) a raw-string opener? Sets the span when it is.
    bool openAt( std::size_t o ) noexcept
    {
        std::size_t p = o;   // the prefix: R, or u8R / uR / UR / LR
        if( p >= 2 && hay_.substr( p - 2, 2 ) == "u8" ) { p -= 2; }
        else if( p >= 1 && ( hay_[ p - 1 ] == 'u' || hay_[ p - 1 ] == 'U' || hay_[ p - 1 ] == 'L' ) ) { --p; }
        if( p > 0 && darkflags::identByte( (unsigned char)hay_[ p - 1 ] ) )
        {
            return false;   // FOO_R"…" is an identifier's tail, not a raw-string prefix
        }
        // a delimiter is at most 16 bytes, so its '(' lies within the next 17 (CodeRabbit 4570578024: an unbounded find made a
        // header of unclosed `R"` candidates quadratic)
        const std::size_t rel = hay_.substr( o + 2, 17 ).find( '(' );
        if( rel == std::string_view::npos || hay_.substr( o + 2, rel ).find_first_of( " \t\n\\)\"" ) != std::string_view::npos )
        {
            return false;   // not a raw-string delimiter (at most 16 characters, none of space, backslash, parens, quote)
        }
        const std::size_t paren = o + 2 + rel;
        std::string       close = ")";
        close.append( hay_.substr( o + 2, rel ) );
        close.push_back( '"' );
        const std::size_t end = hay_.find( close, paren + 1 );
        spanStart_            = o;
        spanEnd_              = end == std::string_view::npos ? hay_.size() : end + close.size();
        return true;
    }

    std::string_view hay_;
    std::size_t      last_      = 0;
    std::size_t      spanStart_ = std::string_view::npos;
    std::size_t      spanEnd_   = std::string_view::npos;
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

// The first line of `hay` whose first whole-word occurrence of `name` satisfies `lineMatches( line, at )`; 0 when none.
template<class LineMatches>
inline std::uint32_t firstLineWhere( std::string_view hay, std::string_view name, LineMatches&& lineMatches )
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
                if( lineMatches( line, inLine ) )
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
        const bool cppPath  = langFacts( langOfPath( ing.files[ fileIndex ] ) ).objectMacrosUnindexed;   // C indexes its macros
        if( !degraded && !cppPath )
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
            LexicalDefHit capped;   // budget: what was read held no definition; the refusal says the scan stopped
            capped.capped = true;
            return capped;
        }
        bool                macro = false;
        darkflags::BlockCommentState comments( *bytes );
        RawStringState               rawStrings( *bytes );
        const std::uint32_t line  = firstLineWhere( *bytes, name, [ & ]( std::string_view text, std::size_t at )
        {
            const std::size_t lineAt = std::size_t( text.data() - bytes->data() );
            if( comments.insideAt( lineAt ) || rawStrings.insideAt( lineAt ) )
            {
                return false;   // a commented-out `#define` (or definition), or one inside a raw string, defines nothing
            }
            macro = cppPath && objectMacroAt( text, at, name.size() );
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
                setErrRatio( hit, h );
            }
            return hit;
        }
    }
    return {};
}

}   // namespace rw
