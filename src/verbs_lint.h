#pragma once

#include <algorithm>   // std::any_of (H8: findings_capped over the emitted rules)
#include <format>      // std::format — the printf-family pilot conversion (see test/printffmtparitycheck.sh)
#include <print>       // std::print — same pilot; zero-dependency C++23. Floor is libstdc++ 14 / gcc-toolset-14
                       // (std::format alone needs only 13): confirmed present on every CI leg as of this commit —
                       // RHEL/UBI9 CI run 33981920823 ("rhel (ubi9, plain)") and the manylinux_2_28 release leg
                       // (DEVTOOLSET_ROOTPATH=/opt/rh/gcc-toolset-14/root) CI run 31665948282 ("build (linux-x64)")
                       // both resolve to gcc-toolset-14; Apple clang 21.0.0 on macOS compiles and runs both. The
                       // RHEL leg's gcc-toolset probe (.github/workflows/ci.yml) is pinned to this floor (>=14),
                       // not merely "whichever toolset exists" — see that file's comment for why the distinction
                       // matters. fmt is NOT vendored: this floor makes the standard library sufficient (G3).
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_lint.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_lint.h — the --lint verb family, moved VERBATIM from main.cpp in the 2026-08-29 split: the
// number/lambda/return body-scan primitives, the symbol-level checks, the rule plumbing (catalog,
// selection, tally, dedupe, heat annotations), the SARIF emitter, the --match/--regex query outcomes
// (their only caller is runLint's dispatch block), and runLint itself. Same contract as every
// verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one unnamed namespace, internal linkage
// unchanged, zero new API surface — and the RIPWIRE_MAIN_TU guard makes a second includer a compile
// error instead of an ODR trap.

namespace
{

// Magic-number filtering is semantic, not spelling-based: decimal forms such as 0.0, 1.0f, 2.0 and
// -1 are the same universal control/count idioms as their integer spellings. Base-prefixed literals are
// an explicit syntax allow-list for masks, protocol fields and character encodings; without type/dataflow
// evidence, calling 0x80 a maintenance defect creates much more noise than signal.
bool isUniversalOrAllowlistedNumber( std::string_view spelling ) noexcept
{
    std::string normalized;
    normalized.reserve( spelling.size() );
    for( char c : spelling )
    {
        if( c != '\'' )
        {
            normalized.push_back( c );
        }
    }

    std::string_view valueText = normalized;
    if( !valueText.empty() && ( valueText.front() == '+' || valueText.front() == '-' ) )
    {
        valueText.remove_prefix( 1 );
    }
    constexpr std::string_view kBasePrefixes[] = { "0x", "0X", "0b", "0B" };
    for( std::string_view prefix : kBasePrefixes )
    {
        if( valueText.rfind( prefix, 0 ) == 0 )
        {
            return true;
        }
    }

    while( !normalized.empty() )
    {
        const char suffix = normalized.back();
        if( suffix != 'u' && suffix != 'U' && suffix != 'l' && suffix != 'L' && suffix != 'f' && suffix != 'F' )
        {
            break;
        }
        normalized.pop_back();
    }
    if( normalized.empty() )
    {
        return false;
    }

    double parsed = 0.0;
    const auto [ end, error ] = rw::parseFloating( normalized.data(), normalized.data() + normalized.size(), parsed );
    if( error != std::errc {} || end != normalized.data() + normalized.size() )
    {
        return false;
    }
    return parsed == -2.0 || parsed == -1.0 || parsed == 0.0 || parsed == 1.0 || parsed == 2.0;
}

// A number captured inside a local const/constexpr initializer is named policy, not a magic number. Walk
// only to the current statement/block boundary: a `const` in an earlier statement must not pardon this one.
bool isConstantInitializerNumber( std::string_view src, std::size_t numberByte ) noexcept
{
    if( numberByte > src.size() )
    {
        return false;
    }
    std::size_t statementStart = numberByte;
    while( statementStart > 0 )
    {
        const char c = src[ statementStart - 1 ];
        if( c == ';' || c == '{' || c == '}' )
        {
            break;
        }
        --statementStart;
    }
    const std::string_view head = src.substr( statementStart, numberByte - statementStart );
    const std::size_t      eq   = head.rfind( '=' );
    if( eq == std::string_view::npos || ( eq > 0 && std::strchr( "=!<>+-*/%&|^~", head[ eq - 1 ] ) != nullptr ) )
    {
        return false;
    }
    return rw::darkflags::containsWord( head.substr( 0, eq ), "constexpr" ) || rw::darkflags::containsWord( head.substr( 0, eq ), "const" );
}

// The raw-body return scanner deliberately avoids a second AST pass. A nested lambda body is the one C++
// callable shape an outer function's byte span contains without a separately indexed Symbol; recognise its
// capture list between the previous statement/block boundary and this opening brace.
bool opensLambdaBody( std::string_view src, std::size_t bodyStart, std::size_t braceByte ) noexcept
{
    std::size_t headStart = braceByte;
    while( headStart > bodyStart )
    {
        const char c = src[ headStart - 1 ];
        if( c == ';' || c == '{' || c == '}' )
        {
            break;
        }
        --headStart;
    }
    const std::string_view head  = src.substr( headStart, braceByte - headStart );
    const std::size_t      close = head.rfind( ']' );
    if( close == std::string_view::npos )
    {
        return false;
    }
    const std::size_t open = head.rfind( '[', close );
    if( open == std::string_view::npos )
    {
        return false;
    }
    std::string_view prefix = rw::darkflags::trimView( head.substr( 0, open ) );
    if( prefix.empty() )
    {
        return true; // immediately-invoked `[]{ ... }()`
    }
    if( rw::darkflags::identByte( (unsigned char)prefix.back() ) )
    {
        const std::size_t returnAt = prefix.size() >= 6 ? prefix.size() - 6 : std::string_view::npos;
        return returnAt != std::string_view::npos && prefix.substr( returnAt ) == "return"
            && ( returnAt == 0 || !rw::darkflags::identByte( (unsigned char)prefix[ returnAt - 1 ] ) );
    }
    return prefix.back() != ']' && prefix.back() != ')';   // `flags[i]` / `(array)[i]` are subscripts, not captures
}

// Return the first bare-return line only when this callable also owns a value return. Nested lambda returns
// are outside that contract even though their bytes lie inside the outer function's indexed span.
std::optional<std::uint32_t> inconsistentReturnLine( std::string_view src, std::uint32_t bodyStart, std::uint32_t bodyEnd ) noexcept
{
    bool hasValue = false, hasBare = false;
    std::uint32_t bareLine = 1, currentLine = rw::layout::lineOf( src, bodyStart );
    std::uint32_t braceDepth = 0, lambdaRootDepth = 0;
    bool          sawOuterBrace = false;
    for( std::uint32_t i = bodyStart; i < bodyEnd; )
    {
        const char c = src[i];
        const std::size_t inertEnd = rw::layout::skipInert( src, i );
        if( inertEnd != i )
        {
            const std::size_t scanEnd = std::min<std::size_t>( inertEnd, bodyEnd );
            currentLine += static_cast<std::uint32_t>( std::count( src.begin() + i, src.begin() + scanEnd, '\n' ) );
            i = static_cast<std::uint32_t>( scanEnd );
            continue;
        }
        if( c == '\n' ) { ++currentLine; ++i; continue; }
        if( c == '{' )
        {
            const bool isLambdaRoot = sawOuterBrace && lambdaRootDepth == 0 && opensLambdaBody( src, bodyStart, i );
            ++braceDepth;
            if( isLambdaRoot )
            {
                lambdaRootDepth = braceDepth;
            }
            sawOuterBrace = true;
            ++i;
            continue;
        }
        if( c == '}' )
        {
            if( lambdaRootDepth == braceDepth )
            {
                lambdaRootDepth = 0;
            }
            if( braceDepth > 0 )
            {
                --braceDepth;
            }
            ++i;
            continue;
        }
        if( lambdaRootDepth == 0 && c == 'r' && i + 6 <= bodyEnd
            && src[i+1]=='e' && src[i+2]=='t' && src[i+3]=='u' && src[i+4]=='r' && src[i+5]=='n'
            && ( i + 6 == bodyEnd || !std::isalnum( (unsigned char)src[i+6] ) && src[i+6] != '_' ) )
        {
            std::uint32_t j = i + 6;
            while( j < bodyEnd && ( src[j] == ' ' || src[j] == '\t' ) )
            {
                ++j;
            }
            if( j < bodyEnd && src[j] == ';' )
            {
                hasBare = true;
                bareLine = currentLine;
            }
            else if( j < bodyEnd && src[j] != '}' )
            {
                hasValue = true;
            }
            i = j;
            continue;
        }
        ++i;
    }
    return hasValue && hasBare ? std::optional<std::uint32_t>( bareLine ) : std::nullopt;
}

// Symbol-level lint checks (S6-A), lifted verbatim out of the --lint block so runLint stays under the
// complexity bar. Walks each C-family Function/Method body for large-function / deep-nesting /
// inconsistent-return; returns the findings the caller merges into the combined lint set.
std::vector<rw::AstMatch> lintSymbolLevelChecks( const rw::IngestResult& ing, const std::vector<std::string>* preRead )
{
    using namespace rw;
            // Build per-file byte map (read each file once).
            // preRead: bytes the caller's corpus walk already holds (astQueryGrouped's keptBytesOut). An
            // empty or missing slot falls through to the read below and yields the same bytes, so the two
            // paths cannot disagree; the size guard keeps a vector built for another corpus in bounds.
            std::vector<std::string> fileBytes( ing.files.size() );
            HashMap<std::uint32_t, bool> fileRead;
            const auto getBytes = [ & ]( std::uint32_t fid ) -> const std::string&
            {
                if( preRead != nullptr && fid < preRead->size() && !( *preRead )[fid].empty() )
                {
                    return ( *preRead )[fid];
                }
                if( fileRead.find( fid ) == fileRead.end() )
                {
                    FILE* fp = std::fopen( diskPath( ing, fid ).c_str(), "rb" );
                    if( fp )
                    {
                        std::fseek( fp, 0, SEEK_END );
                        const long sz = std::ftell( fp );
                        std::fseek( fp, 0, SEEK_SET );
                        if( sz > 0 ) { fileBytes[fid].resize( std::size_t( sz ) ); std::fread( fileBytes[fid].data(), 1, std::size_t( sz ), fp ); }
                        std::fclose( fp );
                    }
                    fileRead[fid] = true;
                }
                return fileBytes[fid];
            };

            // Only check C/C++ functions (SymKind::Function or Method) — the nesting/line checks are
            // most meaningful and least noisy for C-family code. Python/Go/Rust have different idioms.
            // Extension guard: check if the file is a C/C++ source.
            const auto isCFamily = [ & ]( std::uint32_t fid ) -> bool
            {
                const std::string& p = ing.files[fid];
                const std::size_t  d = p.rfind( '.' );
                if( d == std::string::npos )
                {
                    return false;
                }
                const std::string_view ext( p.data() + d );
                return ext == ".c" || ext == ".cpp" || ext == ".cc" || ext == ".cxx"
                    || ext == ".h" || ext == ".hpp" || ext == ".hh" || ext == ".hxx";
            };

            std::vector<AstMatch> symHits;
            for( const Symbol& s : ing.symbols )
            {
                if( s.kind != SymKind::Function && s.kind != SymKind::Method )
                {
                    continue;
                }
                if( s.endByte <= s.sigEndByte )
                {
                    continue; // no body (prototype / abstract)
                }
                if( !isCFamily( s.fileId ) )
                {
                    continue;
                }

                const std::string& src = getBytes( s.fileId );
                if( src.empty() )
                {
                    continue;
                }
                const std::uint32_t bodyA = std::min( s.sigEndByte, std::uint32_t( src.size() ) );
                const std::uint32_t bodyB = std::min( s.endByte,    std::uint32_t( src.size() ) );
                if( bodyB <= bodyA )
                {
                    continue;
                }

                // large-function: count newlines in body span
                {
                    std::uint32_t lines = 0;
                    for( std::uint32_t i = bodyA; i < bodyB; ++i )
                    {
                        if( src[i] == '\n' )
                        {
                            ++lines;
                        }
                    }
                    if( lines > 80 )
                    {
                        AstMatch hit;
                        hit.fileId    = s.fileId;
                        hit.startByte = s.sigStartByte;
                        hit.endByte   = s.endByte;
                        hit.line      = s.line;
                        hit.tag       = "large-function";
                        hit.text      = s.name + " (" + std::to_string( lines ) + " lines)";
                        symHits.push_back( std::move( hit ) );
                    }
                }

                // deep-nesting: track curly-brace depth inside the body, ignoring string/char literals
                // and single-line comments. Report when depth exceeds 4 (the outer body `{` counts as 1).
                {
                    std::uint32_t maxDepth = 0, depth = 0;
                    std::uint32_t deepLine = s.line;
                    std::uint32_t curLine  = s.line;
                    bool          inLineComment = false, inBlockComment = false;
                    char          inString = 0;   // '\0' = not in a string, otherwise the quote char
                    for( std::uint32_t i = bodyA; i < bodyB; ++i )
                    {
                        const char c = src[i];
                        if( c == '\n' ) { ++curLine; inLineComment = false; continue; }
                        if( inLineComment )
                        {
                            continue;
                        }
                        if( inBlockComment )
                        {
                            if( c == '*' && i + 1 < bodyB && src[i + 1] == '/' ) { inBlockComment = false; ++i; }
                            continue;
                        }
                        if( inString != 0 )
                        {
                            if( c == '\\' ) { ++i; continue; }
                            if( c == inString )
                            {
                                inString = 0;
                            }
                            continue;
                        }
                        if( c == '/' && i + 1 < bodyB && src[i + 1] == '/' ) { inLineComment = true; continue; }
                        if( c == '/' && i + 1 < bodyB && src[i + 1] == '*' ) { inBlockComment = true; ++i; continue; }
                        if( c == '"' || c == '\'' ) { inString = c; continue; }
                        if( c == '{' )
                        {
                            ++depth;
                            if( depth > maxDepth ) { maxDepth = depth; deepLine = curLine; }
                        }
                        else if( c == '}' && depth > 0 )
                        {
                            --depth;
                        }
                    }
                    // depth=1 is the outer function body `{` — threshold is >4 meaning depth 5+
                    if( maxDepth > 4 )
                    {
                        AstMatch hit;
                        hit.fileId    = s.fileId;
                        hit.startByte = s.sigStartByte;
                        hit.endByte   = s.endByte;
                        hit.line      = deepLine;
                        hit.tag       = "deep-nesting";
                        hit.text      = s.name + " (max depth " + std::to_string( maxDepth ) + ")";
                        symHits.push_back( std::move( hit ) );
                    }
                }

                // inconsistent-return: the scanner owns the lexical callable-boundary rules; this loop
                // only translates its optional bare-return line into the shared lint finding shape.
                {
                    const std::optional<std::uint32_t> bareReturnLine = inconsistentReturnLine( src, bodyA, bodyB );
                    if( bareReturnLine )
                    {
                        AstMatch hit;
                        hit.fileId    = s.fileId;
                        hit.startByte = s.sigStartByte;
                        hit.endByte   = s.endByte;
                        hit.line      = *bareReturnLine;
                        hit.tag       = "inconsistent-return";
                        hit.text      = s.name + " (bare return in a value-returning function)";
                        symHits.push_back( std::move( hit ) );
                    }
                }
            }   // for each symbol

            // Sort by (file, line) for determinism, then merge into ms.
            std::sort( symHits.begin(), symHits.end(), [ & ]( const AstMatch& x, const AstMatch& y )
                       {
                if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
                if( x.line != y.line ) { return x.line < y.line;
}
                return x.tag < y.tag; } );
            return symHits;
}

// Unified lint finding shape (built-in tags and user rule ids emit identically). sev is empty for
// built-ins (facts, not severities); user findings carry their declared sev=. Lives at file scope
// (not local to runLint) so dedupeLintFindings below can share it.
struct LintOut { std::uint32_t fileId, startByte, line; std::string rule, sev, text; };

// One <rule> tally row. The built-in and user-rule tally loops in runLint differ ONLY in whether sev=
// is present (nullptr ⇒ omitted, a built-in row) — everything else (capped=, and L7's applicable=) is
// identical branching duplicated twice; this is the one copy. Callers pass already-escaped strings
// (name/sev safety differs: built-in names are compile-time-known, user ids/severities are ex()'d at
// the call site) so this stays a pure formatter with no XML-escaping policy of its own.
//
// wave-4 item 12 (the recorded liability from the six-smalls round, docs/EVALS.md): the DEFAULT PAYLOAD
// byte cap (kLintDefaultPayloadBytes above) keeps a sorted PREFIX of `outs`, so a rule whose findings all
// sort past that prefix loses every <f> locator row while its own count= — computed over the full,
// uncapped `outs` — stays a truthful total. Before this, that rule's tally row was indistinguishable from
// one with real locator rows sitting just below the fold; shown_rows= closes the gap by naming exactly how
// many of THIS rule's rows survived the row/byte window the caller actually gets, unconditionally (never
// omitted, so a fully-capped-away rule reads shown_rows="0" instead of silently locator-less) and always
// <= count (== count on an unpaged, uncapped run, or under an explicit --limit/--offset).
//
// NOUN-PREFIXED, not the bare shown=/capped= pair (src/pageview.h, THE TRUNCATION VOCABULARY rule 1's
// exception): this element's bare `capped=` already carries a DIFFERENT fact — this rule's own raw-capture
// stream hit ITS OWN per-rule match budget, so count= itself is a floor — and rule 3 requires the bit
// paired with shown= to describe the SAME truncation event. Conflating the two under one name would make
// capped="1" mean "match-budget floor" on one row and "row-window cut" on the next, indistinguishably;
// shown_rows=/rows_capped= is its own pair (truncvocabcheck.sh rules 1+3) so the two facts stay legible
// side by side rather than colliding under one bit.
// §L10: `compiled` (default true — every built-in query is checked at compile time by test/lintcheck.sh's
// own fixture sweep, never user text) is false only for a USER rule whose tree-sitter query compiled for
// NO linked grammar at all. Before this, that row was a bare count="0" — byte-identical to a well-formed
// query that legitimately matched nothing, with the ONLY tell being a one-line stderr alert a machine
// reader of stdout never sees. compiled="0" makes the distinction part of the row itself.
void printLintRuleTallyRow( const std::string& name, const std::string* sev, std::uint32_t count, std::uint32_t shown, bool capped, bool applicable,
                            bool compiled = true )
{
    const char* sevPart        = "";
    std::string sevBuf;
    if( sev != nullptr )
    {
        sevBuf   = " sev=\"" + *sev + "\"";
        sevPart  = sevBuf.c_str();
    }
    // capture-audit 2026-09-04 (truncvocabcheck arm (F)): the match-budget floor is rule 4's marker on the
    // count= it floors — count_capped="1" — not a BARE capped="1" with no shown= beside it, which read as
    // rule 3's window bit missing its pair. Same fact, the vocabulary's own spelling for it.
    std::print( "<rule name=\"{}\"{} count=\"{}\" shown_rows=\"{}\" rows_capped=\"{}\"{}{}{}/>", name, sevPart, count, shown,
                shown < count ? 1u : 0u, capped ? " count_capped=\"1\"" : "", applicable ? "" : " applicable=\"0\"",
                compiled ? "" : " compiled=\"0\"" );
}

// wave-4 item 12: the (count, shown-inside-`lintPage`) pair for ONE rule's rows in the already-sorted
// `outs`. Lifted out of runLint's two per-rule tally loops (built-in and user) for the same reason
// mergeAtomsPack/dedupeLintFindings/lintSymbolLevelChecks above it were — runLint was already the file's
// largest dispatcher, and this is a second full-`outs` scan per rule either way, not new algorithmic
// weight, just a home outside the function whose size this whole file already works to keep down.
// `wantSevEmpty` is the one distinction between the built-in loop (bare rows, sev.empty()) and the user
// loop (every user finding carries sev=); passing it explicitly keeps this one function instead of two.
struct RuleTally { std::uint32_t count = 0, shown = 0; };
RuleTally tallyLintRule( const std::vector<LintOut>& outs, const std::string& ruleId, bool wantSevEmpty, rw::PageWindow lintPage )
{
    RuleTally t;
    for( std::size_t oi = 0; oi < outs.size(); ++oi )
    {
        const LintOut& m = outs[oi];
        if( m.rule == ruleId && m.sev.empty() == wantSevEmpty )
        {
            ++t.count;
            if( oi >= lintPage.begin && oi < lintPage.end )
            {
                ++t.shown;
            }
        }
    }
    return t;
}

// §P0.2: rules whose RAW capture stream spent its whole per-rule budget — their count= is a floor, not
// a total, and must say so (the contract --match already honours with hits_capped="1"). Keyed by
// (name, namespace): a user rule may share a built-in rule's name, and a cap must never leak across
// that boundary — a bare-name lookup painted `capped="1"` onto rules that were never capped (including
// symbol-level built-ins that have no query budget at all). File scope, like LintOut and for the same
// reason: mergeAtomsPack below fills it too.
struct RuleCap { std::string rule; bool isUserRule; };

// --with-profile (the SYZYGY advice-mode pairing: static shape × PMU weight — Hundt et al., CGO 2006,
// already cited in fieldaffinity.h): one parsed row of the #PROF_TSV block a RIPWIRE_PROFILE build's
// report emits (profileScope.h::print_tsv — scope, file, line, then whatever data columns that run's
// counter tier armed). File scope like LintOut, for the same reason: runLint consumes it.
struct ProfScopeRow
{
    std::string file;      // basename, exactly as PROFILE_SCOPE's Site::file records it
    int         line = 0;  // the PROFILE_SCOPE site line
    std::string scope;     // description text, or the trimmed function name
    std::vector<std::pair<std::string, std::string>> cols;   // header name → raw cell, calls onward
};

// Parse FILE's #PROF_TSV block. nullopt = unreadable file, no sentinel pair, or a header that is not
// the block's own (scope/file/line first) — the caller REFUSES loudly rather than joining nothing
// silently, because "annotated zero findings" and "read the wrong file" must never look alike.
std::optional<std::vector<ProfScopeRow>> parseProfTsv( const std::string& path )
{
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( fp == nullptr )
    {
        return std::nullopt;
    }
    std::string all;
    char        buf[ 4096 ];
    std::size_t got = 0;
    while( ( got = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
    {
        all.append( buf, got );
    }
    std::fclose( fp );

    const auto splitTabs = []( std::string_view lineText )
    {
        std::vector<std::string> cells;
        std::size_t              from = 0;
        for( ;; )
        {
            const std::size_t tab = lineText.find( '\t', from );
            if( tab == std::string_view::npos )
            {
                cells.emplace_back( lineText.substr( from ) );
                return cells;
            }
            cells.emplace_back( lineText.substr( from, tab - from ) );
            from = tab + 1;
        }
    };

    std::vector<ProfScopeRow> rows;
    std::vector<std::string>      header;
    bool inBlock = false, sawEnd = false;
    std::size_t from = 0;
    while( from <= all.size() )
    {
        const std::size_t    nl       = all.find( '\n', from );
        const std::string_view lineText( all.data() + from, ( nl == std::string::npos ? all.size() : nl ) - from );
        from = ( nl == std::string::npos ) ? all.size() + 1 : nl + 1;
        if( !inBlock )
        {
            if( lineText.rfind( "#PROF_TSV_BEGIN", 0 ) == 0 )
            {
                inBlock = true;
            }
            continue;
        }
        if( lineText.rfind( "#PROF_TSV_END", 0 ) == 0 )
        {
            sawEnd = true;
            break;
        }
        if( header.empty() )
        {
            header = splitTabs( lineText );
            if( header.size() < 4 || header[0] != "scope" || header[1] != "file" || header[2] != "line" )
            {
                return std::nullopt;   // not print_tsv's own header — wrong file, refuse
            }
            continue;
        }
        const std::vector<std::string> cells = splitTabs( lineText );
        if( cells.size() < 4 )
        {
            continue;   // a short row carries nothing joinable; skip it rather than invent columns
        }
        ProfScopeRow row;
        row.scope = cells[0];
        row.file  = cells[1];
        row.line  = std::atoi( cells[2].c_str() );
        for( std::size_t cellIndex = 3; cellIndex < cells.size() && cellIndex < header.size(); ++cellIndex )
        {
            row.cols.emplace_back( header[cellIndex], cells[cellIndex] );
        }
        rows.push_back( std::move( row ) );
    }
    if( !inBlock || !sawEnd )
    {
        return std::nullopt;
    }
    return rows;
}


// The --with-profile join itself: annotate each finding with the NEAREST-PRECEDING PROFILE_SCOPE site
// inside its own enclosing symbol (same basename, symbol.line <= site.line <= finding.line — scopes
// lead the region they measure, so a later site never annotates an earlier finding). The measured
// columns are whatever counter tier the profiled run armed; an absent column was NOT measured, never
// zero. Returns the per-finding attribute strings (index-aligned with `outs`) plus the root
// heat_joined= attribute — or nullopt AFTER printing the refusal (unreadable FILE, or no #PROF_TSV
// block), so the caller exits 1: "annotated zero findings" and "read the wrong file" never look alike.
template <class EnclosingFn>
std::optional<std::pair<std::vector<std::string>, std::string>>
buildHeatAnnotations( std::string_view withProfile, const rw::IngestResult& ing, const std::vector<LintOut>& outs, EnclosingFn&& enclosing )
{
    using namespace rw;
    const auto profRows = parseProfTsv( std::string( withProfile ) );
    if( !profRows )
    {
        std::print( stderr, "ripwire: --with-profile={}: no readable #PROF_TSV block there — generate one with a "
                            "RIPWIRE_PROFILE build (ripwire <dir> 2>report.txt), or pass that report verbatim\n",
                    withProfile );
        return std::nullopt;
    }
    std::vector<char> esc;
    const auto        ex     = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    const auto        baseOf = []( std::string_view p ) -> std::string_view
    {
        const std::size_t slash = p.find_last_of( '/' );
        return slash == std::string_view::npos ? p : p.substr( slash + 1 );
    };
    std::vector<std::string> heatByFinding( outs.size() );
    std::size_t              joined = 0;
    for( std::size_t findingIndex = 0; findingIndex < outs.size(); ++findingIndex )
    {
        const LintOut& m = outs[ findingIndex ];
        const Symbol*  e = enclosing( m.fileId, m.startByte );
        if( e == nullptr )
        {
            continue;
        }
        const std::string_view fileBase = baseOf( ing.files[ m.fileId ] );
        const ProfScopeRow*    best     = nullptr;
        for( const ProfScopeRow& row : *profRows )
        {
            if( row.line <= 0 || fileBase != row.file )
            {
                continue;
            }
            if( std::uint32_t( row.line ) < e->line || std::uint32_t( row.line ) > m.line )
            {
                continue;
            }
            if( best == nullptr || row.line > best->line )
            {
                best = &row;
            }
        }
        if( best == nullptr )
        {
            continue;
        }
        ++joined;
        std::string attrs = " heat_scope=\"" + ex( best->scope ) + "\"";
        for( const auto& [ colName, colValue ] : best->cols )
        {
            std::string attrName;
            for( const char c : colName )
            { // XML-safe attribute name: the TSV's own names are safe, but a hand-edited one must not break well-formedness
                attrName += ( std::isalnum( static_cast<unsigned char>( c ) ) || c == '_' ) ? c : '_';
            }
            attrs += " heat_" + attrName + "=\"" + ex( colValue ) + "\"";
        }
        heatByFinding[ findingIndex ] = std::move( attrs );
    }
    return std::make_pair( std::move( heatByFinding ), std::format( " heat_joined=\"{}\"", joined ) );
}

// Fold the atoms-of-confusion pack (src/atoms.h — Gopstein et al., ESEC/FSE 2017) into the built-in
// lint set: its findings, its per-rule floor disclosures, and its rule names for the tally. Three of
// its seven rules are decided by SUBTRACTION ("every update_expression EXCEPT the statement-level and
// for-header ones"), which no tree-sitter query can express, so the pack spends its own astQuery pass
// on a budget far above kLintMaxPerRule — an exclusion stream truncated at 5000 would manufacture
// false positives on this repo alone. kAtomRuleNames is THE list, so the tally cannot drift from what
// ONE parse pass for all four built-in producers, in the order runLint merges them: the [AST] checks it
// was handed, the atoms pack, the cache pack, and the unreachable-code walk. Each of those used to drive
// its OWN corpus pass, and each of those passes re-read and re-parsed every file -- four reads and four
// tree-sitter parses per file to ask four sets of questions about the SAME tree, plus three rounds of
// compiling every spec against every linked grammar. astQueryGrouped walks the corpus once and buckets the
// findings per group; each bucket is then sorted and budget-capped by exactly the code a standalone call
// runs, so the four results are byte-identical to the four passes they replace.
//
// The fourth is not a spec table: unreachable-code is an ORDERED scan of a block's statement siblings
// ("the first non-comment statement after an unconditional exit"), which no tree-sitter pattern can
// express, so it rides the shared walk as an AstWalk group instead (src/ingest.h). What it shares is what
// it was duplicating -- the read, the parse and the newline index -- not the traversal.
// keptBytes receives the corpus text the walk read (astQueryGrouped's keptBytesOut). The two symbol-level
// passes that run after it -- lintSymbolLevelChecks and the naming lens -- each opened the very files this
// walk had just read and closed, one at a time on the main thread, to look at spans of the same text. They
// now read from here and fall back to their own open only for a file the walk skipped.
std::vector<std::vector<rw::AstMatch>> builtInLintCaptures( const rw::IngestResult& ing, const std::vector<rw::AstQuerySpec>& checks,
                                                            std::vector<std::string>& keptBytes )
{
    PROFILE_SCOPE_DESCRIBE( "lint: astQueryGrouped (built-in + atoms + cache + unreachable)" );
    const std::vector<rw::AstQuerySpec> atomChecks  = rw::atoms::atomsSpecs();
    const std::vector<rw::AstQuerySpec> cacheChecks = rw::cachelint::cacheSpecs();
    return rw::astQueryGrouped( ing, { { &checks,      rw::kLintMaxPerRule,              nullptr },
                                       { &atomChecks,  rw::atoms::kAtomsQueryBudget,     nullptr },
                                       { &cacheChecks, rw::cachelint::kCacheQueryBudget, nullptr },
                                       { nullptr,      rw::kUnreachableMaxHits,          nullptr, rw::AstWalk::UnreachableCode } },
                                &keptBytes );
}

// the pack can emit. Lifted out of runLint for the same reason lintSymbolLevelChecks was.
void mergeAtomsPack( const rw::IngestResult& ing, std::vector<rw::AstMatch>& ms,
                     std::vector<RuleCap>& saturatedRules, std::vector<std::string>& allRuleNames,
                     std::vector<rw::AstMatch> captures )
{
    const rw::atoms::AtomsRun pack = rw::atoms::atomsOfConfusionFromCaptures( ing, rw::kLintMaxPerRule, std::move( captures ) );
    for( const rw::AstMatch& hit : pack.findings )      { ms.push_back( hit ); }
    for( const std::string& tag : pack.saturatedTags )  { saturatedRules.push_back( { tag, false } ); }
    for( const std::string_view rule : rw::atoms::kAtomRuleNames ) { allRuleNames.emplace_back( rule ); }
}

// Fold the cache-friendliness pack (src/cachelint.h — the access-pattern half of the locality story;
// the layout half is --field-affinity) into the built-in lint set: its findings, its per-rule floor
// disclosures, and its rule names for the tally. Same shape as mergeAtomsPack for the same reasons.
void mergeCachePack( const rw::IngestResult& ing, std::vector<rw::AstMatch>& ms,
                     std::vector<RuleCap>& saturatedRules, std::vector<std::string>& allRuleNames,
                     std::vector<rw::AstMatch> captures )
{
    const rw::cachelint::CacheRun pack = rw::cachelint::cacheFriendliness( ing, rw::kLintMaxPerRule, std::move( captures ) );
    for( const rw::AstMatch& hit : pack.findings )      { ms.push_back( hit ); }
    for( const std::string& tag : pack.saturatedTags )  { saturatedRules.push_back( { tag, false } ); }
    for( const std::string_view rule : rw::cachelint::kCacheRuleNames ) { allRuleNames.emplace_back( rule ); }
}

// Fold the identifier-naming lens (src/naminglens.h) into the built-in lint set: its findings go straight
// into ms, and a rule that spent its per-rule budget comes back here to be disclosed as a floor. Its rule
// names are NOT appended — unlike the atoms pack they are spelled in runLint's allRuleNames table, because
// the naming rules are symbol-level built-ins that were declared there before the pack existed. Lifted out
// of runLint for the same reason mergeAtomsPack and lintSymbolLevelChecks were.
void mergeNamingLens( const rw::IngestResult& ing, std::vector<rw::AstMatch>& ms, std::vector<RuleCap>& saturatedRules, bool namingLocals,
                      const std::vector<std::string>* preRead )
{
    for( std::string& namingRule : rw::naminglens::appendNamingFindings( ing, rw::kLintMaxPerRule, ms, namingLocals, preRead ) )
    {
        saturatedRules.push_back( { std::move( namingRule ), false } );
    }
}

// --lint-catalog: print the static rule registry (src/lintcatalog.h) and nothing else — needs no
// corpus. Lifted out of runLint for the same reason mergeAtomsPack/mergeNamingLens were: runLint was
// already the file's largest function, and this branch is fully self-contained.
int emitLintCatalog()
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( rw::escapeXml( s, esc ) ); };
    std::print( "<!-- ripwire lint-catalog: the built-in lint rule registry, one row per rule, in the SAME order the plain lint "
                "run's own tally uses. sev/cat/rationale describe the rule; lang= is the language TOKEN SET (the spelling the "
                "lint-rules loader's own language: field accepts) whose grammar can ever satisfy this rule's query or scan — a "
                "STRUCTURAL ceiling, not which languages happen to be in any one corpus (that disclosure is the lint run's own "
                "applicable=/inert_rules=). since= is the ripwire release the rule first shipped in. -->" );
    std::print( "<lintcatalog rules=\"{}\">", rw::lintcatalog::kLintCatalog.size() );
    for( const rw::lintcatalog::LintCatalogRow& row : rw::lintcatalog::kLintCatalog )
    {
        std::print( "<rule name=\"{}\" sev=\"{}\" cat=\"{}\" lang=\"{}\" since=\"{}\">{}</rule>",
                    ex( row.name ), ex( row.severity ), ex( row.category ),
                    ex( rw::lintcatalog::lintCatalogLangList( row.langMask ) ), ex( row.since ),
                    ex( row.rationale ) );
    }
    std::print( "</lintcatalog>" );
    return 0;
}

// --lint-select=/--lint-ignore=PREFIX[,...]: resolve BOTH into a LintSelection, validating every token
// against the combined rule-name pool (the static catalog ∪ whatever user rule ids --lint-rules=DIR
// just loaded ∪ the family stems) — done HERE, not in validateConfig, because a token can legitimately
// name a user rule id that is only known after --lint-rules=DIR has been read. nullopt ⇒ a refusal
// was already printed to stderr; the caller's job is just to `return 1`. Lifted out of runLint for the
// same reason emitLintCatalog was — this block alone was worth a third of runLint's complexity growth.
std::optional<rw::lintcatalog::LintSelection> resolveLintSelection( const rw::Config& cfg, const std::vector<rw::LintRule>& userRules )
{
    rw::lintcatalog::LintSelection sel;
    if( cfg.lintSelect.empty() && cfg.lintIgnore.empty() )
    {
        return sel;   // inactive — every rule kept, nothing to disclose
    }

    std::vector<std::string_view> pool;
    pool.reserve( rw::lintcatalog::kLintCatalog.size() + userRules.size() + rw::lintcatalog::kLintFamilyStems.size() );
    for( const rw::lintcatalog::LintCatalogRow& row : rw::lintcatalog::kLintCatalog ) { pool.push_back( row.name ); }
    for( const rw::LintRule& r : userRules ) { pool.push_back( r.id ); }
    for( std::string_view stem : rw::lintcatalog::kLintFamilyStems ) { pool.push_back( stem ); }

    const auto resolve = [ & ]( std::string_view raw, std::vector<std::string>& tokens, const char* flagName ) -> bool
    {
        if( !rw::lintcatalog::splitLintPrefixList( raw, tokens ) )
        {
            std::print( stderr, "ripwire: {}: malformed PREFIX list (empty entry) — comma-separate PREFIXes, e.g. {}=cache-,goto\n",
                        flagName, flagName );
            return false;
        }
        for( const std::string& tok : tokens )
        {
            if( tok == "*" )
            {
                continue;   // the reserved "everything" sentinel — never itself a rule-name prefix
            }
            const bool found = std::any_of( pool.begin(), pool.end(),
                                            [ & ]( std::string_view n ) { return rw::lintcatalog::lintPrefixMatches( tok, n ); } );
            if( !found )
            {
                const std::string near = rw::lintcatalog::lintNameNearMiss( pool, tok );
                std::string        msg = "ripwire: " + std::string( flagName ) + ": '" + tok + "' matches no rule or family";
                if( !near.empty() )
                {
                    msg += " (did you mean '" + near + "'?)";
                }
                msg += " — see --lint-catalog for the full registry\n";
                std::print( stderr, "{}", msg );
                return false;
            }
        }
        return true;
    };
    if( !resolve( cfg.lintSelect, sel.selectPrefixes, "--lint-select" ) ) { return std::nullopt; }
    if( !resolve( cfg.lintIgnore, sel.ignorePrefixes, "--lint-ignore" ) ) { return std::nullopt; }
    sel.active = true;

    // selected="K of N" counts actual RULES (built-ins + loaded user rules) — the family stems above
    // exist only to widen the near-miss pool and are never rules themselves.
    for( const rw::lintcatalog::LintCatalogRow& row : rw::lintcatalog::kLintCatalog )
    {
        ++sel.totalCount;
        if( rw::lintcatalog::lintSelectionKeeps( sel, row.name ) ) { ++sel.selectedCount; }
    }
    for( const rw::LintRule& r : userRules )
    {
        ++sel.totalCount;
        if( rw::lintcatalog::lintSelectionKeeps( sel, r.id ) ) { ++sel.selectedCount; }
    }
    return sel;
}

// The corpus' own language mask plus how many of the PRINTED <rule> rows (post --lint-select/-ignore
// filtering — a filtered-out rule was never a row, so it cannot be inert either) are structurally
// inert on it: none of the rule's registered languages (lintcatalog.h) are present at all. Lifted out
// of runLint for the same reason resolveLintSelection was.
struct LintApplicability { std::uint32_t corpusLangs = 0; std::size_t inertRuleCount = 0; };

LintApplicability computeLintApplicability( const rw::IngestResult& ing, bool builtinsRan, const std::vector<std::string>& allRuleNames,
                                            const std::vector<rw::LintRule>& userRules, const rw::lintcatalog::LintSelection& sel )
{
    LintApplicability out;
    out.corpusLangs = rw::lintcatalog::corpusLangMask( ing );
    const auto kept  = [ & ]( std::string_view name ) { return !sel.active || rw::lintcatalog::lintSelectionKeeps( sel, name ); };
    if( builtinsRan )
    {
        for( const std::string& rn : allRuleNames )
        {
            if( !kept( rn ) ) { continue; }
            const rw::lintcatalog::LintCatalogRow* row = rw::lintcatalog::lintCatalogFind( rn );
            if( row != nullptr && ( row->langMask & out.corpusLangs ) == 0 ) { ++out.inertRuleCount; }
        }
    }
    for( const rw::LintRule& r : userRules )
    {
        if( !kept( r.id ) ) { continue; }
        if( ( rw::langBit( r.lang ) & out.corpusLangs ) == 0 ) { ++out.inertRuleCount; }
    }
    return out;
}

// THE emitted order of --lint's rows: (file path, startByte, rule, sev, text). sev and text are part of
// the KEY, not decoration. (file, startByte, rule) alone is NOT a total order — one rule can emit two
// findings at the same byte (naming-confusable pairs `rbegin` with both `begin` and `cbegin`, both
// anchored at the symbol's own offset) — and std::sort is unstable, so tied rows came out in whatever
// order the producers happened to have appended them. That made a VISIBLE part of the output depend on
// the order the checks run in rather than on the data: a determinism contract held by accident, and it
// flipped the moment the two built-in packs were merged from one call site instead of two. Everything a
// reader can SEE is now in the key, so rows that still tie are byte-identical and dedupeLintFindings
// collapses them. Lifted out of runLint for the same reason dedupeLintFindings was.
void sortLintRows( const rw::IngestResult& ing, std::vector<LintOut>& outs )
{
    std::sort( outs.begin(), outs.end(), [ & ]( const LintOut& x, const LintOut& y )
    {
        if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId]; }
        if( x.startByte != y.startByte )                 { return x.startByte < y.startByte; }
        if( x.rule != y.rule )                           { return x.rule < y.rule; }
        if( x.sev != y.sev )                             { return x.sev < y.sev; }
        return x.text < y.text;
    } );
}

// §P6.1: two DIFFERENT AST captures (different startByte — e.g. the same magic-number value
// spelled twice on one line, `h >> 33` appearing twice in the same expression) can still render
// as a byte-identical <f> row, because the row carries only file:line — no column — so a reader
// cannot tell them apart. A second identical row adds no information a reader can act on
// differently from the first, so collapse on the row's own visible identity (rule, sev,
// file:line, enclosing symbol, text) — keep the first occurrence in the caller's already-
// deterministic sort order. This also keeps findings= and each rule's count= truthful: they
// count distinct VISIBLE findings, not raw captures. Lifted out of the --lint block (same reason
// as lintSymbolLevelChecks above) so runLint stays under the complexity/verbosity bar.
std::vector<LintOut> dedupeLintFindings( const rw::IngestResult& ing, std::vector<LintOut> outs )
{
    using namespace rw;
    // model.h::symbolsByFile — same scan order, same comparator as the hand-written loop it replaces.
    const SymbolsByFile fileSyms = symbolsByFile( ing,
                                                  []( const Symbol& ) { return true; },
                                                  [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
    const auto enclosing = [ & ]( std::uint32_t f, std::uint32_t off ) -> const Symbol*
    {
        const Symbol* best = nullptr;
        for( NodeId id : fileSyms[f] )
        {
            const Symbol& s = ing.symbols[id];
            if( s.sigStartByte > off )
            {
                break;
            }
            if( off < s.endByte && ( !best || s.sigStartByte > best->sigStartByte ) )
            {
                best = &s;
            }
        }
        return best;
    };

    HashMap<std::string, char> seenRow;
    std::vector<LintOut>       deduped;  deduped.reserve( outs.size() );
    for( const LintOut& o : outs )
    {
        const Symbol* e = enclosing( o.fileId, o.startByte );
        std::string   key;
        key.reserve( o.rule.size() + o.sev.size() + ing.files[ o.fileId ].size() + o.text.size() + 32 );
        key += o.rule;                                key += '\x1f';
        key += o.sev;                                 key += '\x1f';
        key += ing.files[ o.fileId ];                 key += '\x1f';
        key += std::to_string( o.line );              key += '\x1f';
        key += e ? e->name : std::string();           key += '\x1f';
        key += o.text;
        if( seenRow.find( key ) != seenRow.end() )
        {
            continue; // same visible row already kept
        }
        seenRow.emplace( std::move( key ), 0 );
        deduped.push_back( o );
    }
    return deduped;
}

// --sarif: build the SARIF rule catalogue + finding list from the SAME `outs` / `allRuleNames` /
// `userRules` / `saturatedRules` runLint's XML path already computed, and emit it (src/sarif.h).
// Lifted out of runLint for the same reason lintSymbolLevelChecks / dedupeLintFindings /
// buildHeatAnnotations above were — pure re-serialization, zero new analysis, and runLint was already
// the file's largest verb. `capOf` is redefined locally (a small linear scan over `saturatedRules`,
// mirroring runLint's own) rather than shared by reference, so this stays a self-contained call.
// The two per-rule DISCLOSURES the XML path states and this one has to state differently. Both are read
// off the SAME inputs the XML arm below uses (lintSelectionKeeps for the row it would have dropped,
// lintCatalogFind ∧ corpusLangs for its applicable="0"), never recomputed from a second source of truth —
// see sarif.h's own header for why SARIF spells them as defaultConfiguration.enabled / properties.applicable
// instead of "omit the row" / "omit the attribute".
// `d` replaces the ing/root/cfg trio this used to take one by one — the same MainDispatch every other verb
// handler in this file is already given, and the reason the two new disclosures below cost no signature
// growth: the run's flags (builtinsActive, the raw select=/ignore=) are fields of d.cfg, so the next fact
// the XML root grows will not widen this signature either.
template <class EnclosingFn>
void emitRunLintSarif( const MainDispatch& d,
                       const std::vector<std::string>& allRuleNames, const std::vector<rw::LintRule>& userRules,
                       const std::vector<RuleCap>& saturatedRules, const std::vector<LintOut>& outs,
                       const rw::lintcatalog::LintSelection& lintSel, std::uint32_t corpusLangs,
                       EnclosingFn&& enclosing )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const auto capOf = [ & ]( const std::string& ruleName, bool isUserRule ) -> const RuleCap*
    {
        for( const RuleCap& rc : saturatedRules )
        {
            if( rc.rule == ruleName && rc.isUserRule == isUserRule )
            {
                return &rc;
            }
        }
        return nullptr;
    };
    const auto keptBySelection = [ & ]( std::string_view name ) noexcept
    {
        return !lintSel.active || rw::lintcatalog::lintSelectionKeeps( lintSel, name );
    };

    std::vector<rw::sarif::SarifRuleDecl> sarifRules;
    sarifRules.reserve( allRuleNames.size() + userRules.size() );
    if( cfg.lint )   // built-in rule catalogue only enters the tally under --lint (mirrors the XML arm)
    {
        for( const std::string& rn : allRuleNames )
        {
            const rw::lintcatalog::LintCatalogRow* catRow = rw::lintcatalog::lintCatalogFind( rn );
            const bool applicable = catRow == nullptr || ( catRow->langMask & corpusLangs ) != 0;
            sarifRules.push_back( { rn, false, capOf( rn, false ) != nullptr, keptBySelection( rn ), applicable } );
        }
    }
    for( const LintRule& r : userRules )
    {
        const bool applicable = ( rw::langBit( r.lang ) & corpusLangs ) != 0;
        sarifRules.push_back( { r.id, true, capOf( r.id, true ) != nullptr, keptBySelection( r.id ), applicable } );
    }

    std::vector<rw::sarif::SarifFinding> sarifFindings;
    sarifFindings.reserve( outs.size() );
    for( const LintOut& m : outs )
    {
        const Symbol* e = enclosing( m.fileId, m.startByte );
        sarifFindings.push_back( { m.rule, m.sev, ing.files[ m.fileId ], m.line, e ? e->name : std::string(), m.text } );
    }

    rw::sarif::SarifRunProperties props;
    // H8: over the EMITTED rules only — the XML root's findings_capped= applies the same predicate.
    props.anyRuleCapped   = std::any_of( saturatedRules.begin(), saturatedRules.end(), [ & ]( const RuleCap& rc )
                                         { return !lintSel.active || rw::lintcatalog::lintSelectionKeeps( lintSel, rc.rule ); } );
    props.selectionActive = lintSel.active;
    props.selectedCount   = lintSel.selectedCount;
    props.totalCount      = lintSel.totalCount;
    props.select.assign( cfg.lintSelect );
    props.ignore.assign( cfg.lintIgnore );
    rw::sarif::emitLintSarif( stdout, sarifRules, sarifFindings, props, d.root );
}

// §L3 / octocode F3: everything one --match run answers with, as ONE structured-binding-friendly return
// (CONTRIBUTING.md §3 Interfaces) instead of a growing out-param list — matches/uncompiled/grammarsAttr/
// eligibleFiles/nearestKind/nearestGrammar are all facts about the SAME query, so a caller reading five
// separate by-ref writes was already the wrong shape before this fix added a sixth.
struct MatchQueryOutcome
{
    std::vector<rw::AstMatch> matches;
    std::vector<std::string>  uncompiled;      // non-empty ⇒ the query compiled for NO grammar, refuse
    std::string                grammarsAttr;    // §L3: pre-joined, see AstQueryGroup::grammarsOut
    std::size_t                eligibleFiles = 0;
    std::string                nearestKind;     // octocode F3: "" when no candidate was close enough
    std::string                nearestGrammar;  // "" alongside a "" nearestKind
};

// Runs a --match query and reports the grammar-applicability disclosure (see AstQueryGroup::grammarsOut/
// eligibleFilesOut in ingest.h and mcprefusal.h's joinClauses), so a query that compiles for SOME grammars
// but none are present in the corpus can say so instead of reporting a bare hits="0" indistinguishable from
// "this pattern does not occur" (§P0.1's gap, one level up the stack). Standalone so runLint's own
// dispatcher body, already one of the largest in this file, doesn't grow by the plumbing.
static MatchQueryOutcome runMatchQuery( const rw::IngestResult& ing, const std::string& matchQuery, std::size_t maxHits )
{
    const std::vector<rw::AstQuerySpec> specs{ { matchQuery, std::string() } };
    MatchQueryOutcome                   out;
    std::vector<std::string>            grammarsOut, nearestKinds, nearestGrammars;
    rw::AstQueryGroup                   grp;
    grp.specs             = &specs;
    grp.maxMatches        = maxHits;
    grp.uncompiledOut     = &out.uncompiled;
    grp.grammarsOut       = &grammarsOut;
    grp.eligibleFilesOut  = &out.eligibleFiles;
    grp.nearestKindOut    = &nearestKinds;      // octocode F3: parallel to uncompiledOut — a one-spec caller
    grp.nearestGrammarOut = &nearestGrammars;   // ever gets at most one entry in either
    out.matches = std::move( rw::astQueryGrouped( ing, { grp } )[0] );
    out.grammarsAttr = rw::mcprefuse::joinClauses( std::vector<std::string_view>( grammarsOut.begin(), grammarsOut.end() ), "," );
    if( !nearestKinds.empty() )    { out.nearestKind    = std::move( nearestKinds[0] ); }
    if( !nearestGrammars.empty() ) { out.nearestGrammar = std::move( nearestGrammars[0] ); }
    return out;
}

// Join owned strings through the ONE joiner the refusal surfaces already use, so a list this file prints
// and a list an MCP refusal prints cannot drift in spelling. (joinClauses takes views; every caller here
// holds owned strings, and hand-rolling the conversion at each call site is how they drift.)
static std::string joinOwned( const std::vector<std::string>& parts, const char* sep )
{
    return rw::mcprefuse::joinClauses( std::vector<std::string_view>( parts.begin(), parts.end() ), sep );
}

// The pattern verb's schema legend, named and hoisted out of runLint: a fifteen-line string literal inside
// an already-large dispatcher body is verbosity the reader pays for at every OTHER verb in that function,
// and a legend nobody can grep for by name is one nobody audits. No literal flag spelling in it — a `-`
// pair is illegal inside an XML comment.
inline constexpr std::string_view kPatternLegend =
    "<!-- ripwire pattern: structural search written in CODE, not in tree-sitter node kinds; each hit = a matching "
                         "node + its enclosing symbol. q= is the pattern as received. grammars= names every served grammar the pattern "
                         "resolved for and shapes= the node KIND it became in each, so what was actually searched for is auditable; "
                         "unsupported= names the families this verb does not serve at all (a zero there would be a lie, so it never "
                         "reports one). Every grammar name here is per grammar OBJECT, so a dialect that borrows another's templates "
                         "is spelled apart from it (cpp/cu = the CUDA grammar, typescript/tsx = the TSX one); a bare cpp NEVER stands "
                         "for its dialects. eligible_files= = corpus files whose grammar the pattern resolved for, i.e. the files "
                         "actually SCANNED; skipped_files= = files in a served language it did NOT resolve for, which were never read "
                         "at all; of_files= = total indexed files. $NAME binds one node and the same $NAME twice must match "
                         "structurally; $_ binds nothing; the ellipsis is matched by a single first-match-wins probe (never an "
                         "exhaustive search) under the disclosed ellipsis_bound sibling cap. Comments are transparent on both sides; "
                         "everything else is kind- and text-exact. unresolved_in= names the served grammars the pattern did not "
                         "resolve for, and appears whenever that could mislead - on a zero result (the zero may be theirs, not the "
                         "code's) or on any run with skipped_files above zero. shown=/capped= = rows printed vs found. hits= is a "
                         "FLOOR, not a total, when EITHER hits_capped=\"1\" (engine match limit reached; the root then also carries "
                         "counts_floor=\"1\" and capped=\"1\" — rows exist that no page holds) or ellipsis_capped=\"1\"; "
                         "the latter means an ellipsis probe gave up on ellipsis_skipped= candidate nodes whose sibling run exceeded "
                         "ellipsis_bound, so a node that would have matched can be missing (ellipsis_skipped= counts ABANDONS and is "
                         "itself a floor on those nodes). raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->";

// R2 — everything ONE pattern run answers with before a byte is emitted, as one structured return (the
// same shape, and the same reason, as MatchQueryOutcome above). A non-empty `refusal` is the whole result:
// the caller prints it and exits 1, and no <pattern> element is ever opened.
struct PatternSearchOutcome
{
    std::vector<rw::AstMatch> matches;
    std::string               refusal;         // non-empty ⇒ refuse; already ends in a newline
    std::string               grammarsAttr;    // resolved grammar names, joined
    std::string               shapesAttr;      // "name:node_kind" per resolved grammar, joined
    std::string               ellipsisAttr;    // "" unless the pattern uses an ellipsis
    std::string               unresolvedAttr;  // "" unless some served grammar did not resolve
    std::size_t               eligibleFiles = 0;
    std::size_t               skippedFiles  = 0;   // served-language files this pattern never scanned (V-3)
    bool                      ellipsisCapped = false;   // an ellipsis probe abandoned a node at the bound (V-2)
    std::uint64_t             ellipsisSkipped = 0;      // how many times — a floor on the nodes left unevaluated
};

// Compile the pattern for every served grammar, decide refusal-or-proceed, run the walk, and assemble the
// disclosures. The refusal path is the load-bearing half: §P0.1's rule one level out — a pattern nothing
// could ask is not a zero, it is a refusal — and the served / not-served lists ride the message so the fix
// arrives in the same breath as the fault.
static PatternSearchOutcome runPatternSearch( const rw::IngestResult& ing, std::string_view rawPattern )
{
    PatternSearchOutcome                      out;
    const std::vector<rw::pattern::GrammarRow> rows     = rw::supportedPatternGrammars();
    const rw::pattern::CompileOutcome          compiled = rw::pattern::compileAll( rawPattern, rows );
    if( !compiled.ok )
    {
        out.refusal = "ripwire: --pattern: " + compiled.err + " (pattern as received: " + std::string( rawPattern ) + ")"
                      + " — served grammars: " + joinOwned( rw::pattern::servedNames( rows ), "," )
                      + "; not served: " + std::string( rw::pattern::kUnsupportedGrammars ) + "\n";
        return out;
    }
    const rw::pattern::PatternProgramSet& progs = compiled.set;

    std::atomic<std::uint64_t> ellipsisCapped{ 0 };

    rw::AstQueryGroup grp;
    grp.walk              = rw::AstWalk::Pattern;
    grp.patternPrograms   = &progs;
    grp.maxMatches        = rw::pattern::kMaxHits;
    grp.ellipsisCappedOut = &ellipsisCapped;
    out.matches           = std::move( rw::astQueryGrouped( ing, { grp } )[0] );

    out.ellipsisSkipped = ellipsisCapped.load( std::memory_order_relaxed );
    out.ellipsisCapped  = out.ellipsisSkipped != 0;

    out.grammarsAttr                 = joinOwned( rw::pattern::resolvedNames( progs ), "," );
    out.shapesAttr                   = joinOwned( rw::pattern::resolvedShapes( progs ), "," );
    const rw::PatternFileCensus cens = rw::eligiblePatternFiles( ing, progs );
    out.eligibleFiles                = cens.eligibleCount;
    out.skippedFiles                 = cens.skippedCount;
    // Both attributes below are emitted ONLY when they are facts about THIS pattern: an ellipsis fact on a
    // pattern with no ellipsis, or a partial-resolution note on a run that found plenty, is decoration —
    // and decoration is how a reader learns to stop reading attributes. unresolved_in= in particular is
    // ast-grep's PatternHasError posture: a partial resolution only MISLEADS when the answer is zero, so
    // the caller withholds it unless the row list is empty.
    if( progs.usesEllipsis )
    {
        // ellipsis_capped=/ellipsis_skipped= ride the same condition as ellipsis_bound= — they are facts
        // about an ellipsis run and decoration on anything else — but unlike the bound they are facts about
        // THIS run. ellipsis_capped= is always spelled, 0 or 1, exactly like hits_capped=/capped=: a
        // disclosure that only appears when it is bad teaches the reader to skim past it.
        out.ellipsisAttr = " ellipsis=\"first-match\" ellipsis_bound=\"" + std::to_string( rw::pattern::kEllipsisBound ) + "\""
                           + " ellipsis_capped=\"" + ( out.ellipsisCapped ? "1" : "0" ) + "\""
                           + " ellipsis_skipped=\"" + std::to_string( out.ellipsisSkipped ) + "\"";
    }
    if( !progs.unresolved.empty() )
    {
        out.unresolvedAttr = " unresolved_in=\"" + joinOwned( progs.unresolved, "," ) + "\"";
    }
    return out;
}

// octocode F3: the "compiled for no grammar" refusal's optional trailer — "" when nearestKind is empty (no
// candidate node-kind token in the query landed within the edit-distance cutoff of any linked grammar's
// vocabulary), which reads exactly as the refusal did before this fix (an honest "no plausible near-miss",
// never a guess). Extracted so the refusal call site stays a single fprintf, not a nested if beside it.
static std::string matchNearestKindClause( const std::string& kind, const std::string& grammar )
{
    if( kind.empty() )
    {
        return std::string();
    }
    std::string clause = " — nearest_kind=\"" + kind + "\"";
    if( !grammar.empty() )
    {
        clause += " grammar=\"" + grammar + "\"";
    }
    return clause;
}

std::optional<int> runLint( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — --lint's
    // OWN --sarif re-serialization (writeSarifResult) already applies it; this brings the native --match/
    // --lint XML forms into parity rather than leaving them the only two still absolute per row.
    const bool         lintSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  lintRootPrefix = lintSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  lintRootEsc;
    const std::string  lintRootAttr   = lintSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], lintRootEsc ) ) + "\"" ) : std::string();

    // --lint-catalog: the built-in rule registry, standalone — needs no corpus at all (lintcatalog.h's
    // table is static), so it is handled before the match/lint/lint-rules setup below even starts.
    if( cfg.lintCatalog )
    {
        return emitLintCatalog();
    }

    // --match=QUERY (structural search) and --lint (built-in checks) both ride the shared AST-query pass and
    // annotate each hit with its enclosing symbol — so they share this setup.
    if( !cfg.match.empty() || !cfg.pattern.empty() || cfg.lint || !cfg.lintRulesDir.empty() )
    {
        // model.h::symbolsByFile — same scan order, same comparator as the hand-written loop it replaces.
        const SymbolsByFile fileSyms = symbolsByFile( ing,
                                                      []( const Symbol& ) { return true; },
                                                      [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
        const auto enclosing = [ & ]( std::uint32_t f, std::uint32_t off ) -> const Symbol*
        {
            const Symbol* best = nullptr;
            for( NodeId id : fileSyms[f] )
            {
                const Symbol& s = ing.symbols[id];
                if( s.sigStartByte > off )
                {
                    break;
                }
                if( off < s.endByte && ( !best || s.sigStartByte > best->sigStartByte ) )
                {
                    best = &s;
                }
            }
            return best;
        };
        const auto emitEscaped = []( const std::string& s )
        {
            for( char ch : s )
            {
                if( ch == '<' )
                {
                    std::fputs( "&lt;", stdout );
                }
                else if( ch == '>' )
                {
                    std::fputs( "&gt;", stdout );
                }
                else if( ch == '&' )
                {
                    std::fputs( "&amp;", stdout );
                }
                else
                {
                    std::fputc( ch, stdout );
                }
            }
        };
        std::vector<char> esc;
        const auto        ex  = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        const int         cap = cfg.packTopN > 0 ? cfg.packTopN : 100;

        if( !cfg.match.empty() )   // structural search: the user's tree-sitter query (≥1 @capture)
        {
            // P2.1: the listing stops at `cap` (--pack-top-n, default 100) while hits= counted everything the
            // engine collected — a `hits="5000"` header over 100 rows said nothing about the other 4900.
            // And hits= is itself bounded by astQuery's own maxMatches, so `hits="5000"` is a FLOOR, not a
            // total; hits_capped= says which of the two it is (same contract as --grep's).
            // §P0.1: astQuery reports CAPTURES, so a query binding none matches nothing it can report —
            // `--match='(if_statement)'` produced a clean, confident hits="0" next to 5000 for the same
            // query with `@i`. A capture-less bare zero must be unreachable: auto-capture the query when
            // appending a capture is provably what the user would have typed (exactly one top-level
            // pattern), and refuse loudly otherwise. Never scan a query we did not understand.
            std::string matchQuery( cfg.match );
            bool        autoCaptured = false;
            {
                const AstQueryShape shape = astQueryShape( matchQuery );
                if( !shape.hasCapture )
                {
                    // A `;` comment makes appending unsafe (` @m` on the end of a comment line is itself
                    // commented out), so a capture-less query that carries one is refused, not guessed at.
                    if( !shape.isSingleTopLevel || shape.hasComment )
                    {
                        // Deliberately does NOT assert a cause: this branch catches several top-level
                        // patterns, zero patterns, and a mis-quoted query alike, and naming the wrong one
                        // would be its own small fabrication. Show the query as received and let the
                        // reader see the stray quote / second pattern for themselves.
                        std::print( stderr, "ripwire: --match: this query captures nothing — add @name, e.g. '(if_statement) @m'. "
                                            "ripwire auto-captures only a query that is exactly ONE top-level pattern, and will not guess for this one "
                                            "(query as received: {})\n",
                                    matchQuery );
                        return 1;
                    }
                    matchQuery  += " @m";
                    autoCaptured = true;
                }
            }
            constexpr std::size_t        kMatchMaxHits = 5000;   // astQuery's per-spec budget, named not implied
            const MatchQueryOutcome      mq = runMatchQuery( ing, matchQuery, kMatchMaxHits );
            const std::vector<AstMatch>& ms            = mq.matches;
            const std::string&           grammarsAttr  = mq.grammarsAttr;   // §L3: which grammars the query compiled against
            const std::size_t&           eligibleFiles = mq.eligibleFiles;
            // §P0.4's rule, applied to --match's own engine: a query no grammar compiled measured NOTHING,
            // so a hits="0" here would be a failure wearing a result. Refuse, exactly like an invalid --regex.
            if( !mq.uncompiled.empty() )
            {
                std::print( stderr, "ripwire: --match: the query compiled for no grammar — refusing rather than reporting a zero it did not measure "
                                    "(query as received: {}){}\n",
                            cfg.match, matchNearestKindClause( mq.nearestKind, mq.nearestGrammar ) );
                return 1;
            }
            // §P8 G3: --match was missed when its sibling --grep got paging — `--limit=5` still emitted the
            // full 100-row cap, so the two structurally identical search verbs disagreed about whether
            // --limit meant anything. Same window, same disclosure, same default cap (--pack-top-n, else
            // 100): pageDisclosure emits exactly the ` shown= capped=` bytes this tag used to hand-roll, so
            // an un-paginated --match is byte-identical. See src/pageview.h, THE TRUNCATION VOCABULARY.
            const PageWindow  matchPage  = pageWindow( ms.size(), effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
            const std::size_t matchShown = matchPage.end - matchPage.begin;
            char              mpab[ kPageDisclosureCap ];
            // §L3: no `attr="value"` spelled out below for grammars=/eligible_files=/of_files= — a naive
            // whole-line grep (matchcapturecheck.sh's own idiom) would match the WORDED example first.
            std::print( "<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. "
                        "shown=/capped= = rows printed vs found; hits_capped=\"1\" ⇒ hits= is a FLOOR (engine match limit reached) and the "
                        "root then also carries counts_floor=\"1\" and capped=\"1\" — rows exist that NO page holds (the engine cap, not the "
                        "window, dropped them; narrow the query), while has_more= keeps its window meaning so a loop still terminates. "
                        "auto_captured=\"1\" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. "
                        "grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that "
                        "language set vs total indexed files. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->" );
            std::print( "<match hits=\"{}\"{} hits_capped=\"{}\"{} grammars=\"{}\" eligible_files=\"{}\" of_files=\"{}\"{}>",
                        ms.size(),
                        pageDisclosure( mpab, sizeof( mpab ), matchShown, ms.size(), matchPage.end,
                                        cfg.pageLimit, cfg.pageOffset, true, kXmlPageSyntax,
                                        /*collectionCapped=*/ ms.size() >= kMatchMaxHits ),   // H8: the same cap hits_capped= names
                        ms.size() >= kMatchMaxHits ? 1 : 0,
                        autoCaptured ? " auto_captured=\"1\"" : "",
                        ex( grammarsAttr ),
                        eligibleFiles,
                        ing.files.size(),
                        lintRootAttr );
            for( std::size_t hitIndex = matchPage.begin; hitIndex < matchPage.end; ++hitIndex )
            {
                const AstMatch&         m  = ms[ hitIndex ];
                const Symbol*           e  = enclosing( m.fileId, m.startByte );
                const std::string_view  rp = lintSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ m.fileId ], lintRootPrefix ) : std::string_view( ing.files[ m.fileId ] );
                std::print( "<m p=\"{}:{}\" in=\"{}\">", ex( rp ), m.line, e ? ex( e->name ) : "" );
                emitEscaped( m.text );
                std::print( "</m>" );
            }
            std::print( "</match>" );
            return 0;
        }

        // R2 — the PATTERN surface: structural search written in CODE instead of in node kinds.
        // Sits here, beside --match, because it answers the same question through the same walk and must
        // emit through the same conventions (enclosing symbol, page window, grammar applicability). The
        // work BEFORE the walk — compile per grammar, refuse or proceed, assemble the disclosures — is
        // runPatternSearch, extracted for exactly the reason runMatchQuery was: runLint's dispatcher body
        // is already one of the largest in this file and must not grow a verb's worth of plumbing.
        if( !cfg.pattern.empty() )
        {
            const PatternSearchOutcome ps = runPatternSearch( ing, cfg.pattern );
            if( !ps.refusal.empty() )
            {
                std::print( stderr, "{}", ps.refusal );
                return 1;
            }
            const PageWindow  patPage  = pageWindow( ps.matches.size(), effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
            const std::size_t patShown = patPage.end - patPage.begin;
            char              ppab[ kPageDisclosureCap ];
            std::print( "{}", kPatternLegend );
            // unresolved_in= is withheld only when it could not mislead: a run that found matches AND read
            // every file it serves. The moment a served-language file went unscanned (skipped_files>0), the
            // partial resolution is exactly what explains it, hits>0 or not — V-3's second case, where a
            // matched .tsx sat beside a silently unread .ts.
            const bool tellUnresolved = ps.matches.empty() || ps.skippedFiles > 0;
            std::print( "<pattern hits=\"{}\"{} hits_capped=\"{}\" q=\"{}\" grammars=\"{}\" shapes=\"{}\" unsupported=\"{}\"{}{} eligible_files=\"{}\" skipped_files=\"{}\" of_files=\"{}\"{}>",
                        ps.matches.size(),
                        pageDisclosure( ppab, sizeof( ppab ), patShown, ps.matches.size(), patPage.end, cfg.pageLimit, cfg.pageOffset, true,
                                        kXmlPageSyntax, /*collectionCapped=*/ ps.matches.size() >= rw::pattern::kMaxHits ),   // H8
                        ps.matches.size() >= rw::pattern::kMaxHits ? 1 : 0,
                        ex( cfg.pattern ),
                        ex( ps.grammarsAttr ),
                        ex( ps.shapesAttr ),
                        rw::pattern::kUnsupportedGrammars,
                        ps.ellipsisAttr,
                        tellUnresolved ? ps.unresolvedAttr : std::string(),
                        ps.eligibleFiles,
                        ps.skippedFiles,
                        ing.files.size(),
                        lintRootAttr );
            for( std::size_t hitIndex = patPage.begin; hitIndex < patPage.end; ++hitIndex )
            {
                const rw::AstMatch&    m  = ps.matches[ hitIndex ];
                const Symbol*          e  = enclosing( m.fileId, m.startByte );
                const std::string_view rp = lintSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ m.fileId ], lintRootPrefix ) : std::string_view( ing.files[ m.fileId ] );
                std::print( "<m p=\"{}:{}\" in=\"{}\">", ex( rp ), m.line, e ? ex( e->name ) : "" );
                emitEscaped( m.text );
                std::print( "</m>" );
            }
            std::print( "</pattern>" );
            return 0;
        }

        // --lint: built-in single-capture [AST]-only checks (C-family). Descriptive — facts, not gates;
        // never the [FLOW]/[TYPE] checks ripwire can't see soundly.
        //
        // S6-A: added 4 new AST-query checks + 3 symbol-level checks (large-function, deep-nesting,
        // inconsistent-return) that require body-text analysis beyond what a single tree-sitter capture gives.
        // Checks skipped (too noisy / require real semantics):
        //   missing-const — needs type inference + mutation analysis ([TYPE]) — false positives on out-params
        //   non-virtual-dtor — needs inheritance graph ([TYPE]) — not reliably detectable from the AST alone
        //   implicit-bool-conv — `if(ptr)` is idiomatic C++; flagging it produces near-universal noise
        std::vector<AstMatch> ms;   // combined findings (built-in tags + user rule ids); shared by both sources

        std::vector<RuleCap> saturatedRules;   // see the RuleCap declaration at file scope for why the key is a PAIR

        // All BUILT-IN rule names in declaration order — drives the per-rule tally in the XML header.
        // Symbol-level checks are appended after the query-based checks; order matches the conceptual list.
        // Declared BEFORE the --lint block so the atoms pack can append its own names from inside it (one
        // guarded region instead of two, which is also what keeps runLint's branch count from growing per pack).
        std::vector<std::string> allRuleNames = {
            "c-style-cast", "goto", "do-while", "unsafe-c-fn", "weak-crypto", "redundant-parens",
            "suspicious-semicolon", "typedef-over-using", "magic-number", "empty-catch", "self-assign",
            "large-function", "deep-nesting", "inconsistent-return", "unreachable-code",
            "naming-short", "naming-wordy", "naming-series", "naming-underscore", "naming-case",
            "naming-predicate", "naming-setter", "naming-confusable", "naming-uninformative",
        };

        if( cfg.lint )   // built-in [AST] checks only run with --lint; --lint-rules alone emits user findings only
        {
        const std::vector<AstQuerySpec> checks = {
            { "(cast_expression) @c",                                                                       "c-style-cast" },         // cppcoreguidelines-pro-type-cstyle-cast
            { "(goto_statement) @c",                                                                        "goto" },                  // cppcoreguidelines-avoid-goto
            { "(do_statement) @c",                                                                          "do-while" },              // cppcoreguidelines-avoid-do-while
            { "(call_expression function: (identifier) @c (#match? @c \"^(strcpy|strcat|sprintf|gets)$\"))","unsafe-c-fn" },           // bugprone unbounded C string fns
            { "(call_expression function: (identifier) @c (#match? @c \"^(MD5|md5|SHA1|sha1|MD4|md4|RC4|rc4)$\"))","weak-crypto" },   // broken hash/cipher (the one [AST] security item; insecure rand() excluded — too noisy)
            { "(parenthesized_expression (parenthesized_expression) @c)",                                   "redundant-parens" },      // clang-tidy readability-redundant-parentheses
            { "(if_statement consequence: (expression_statement) @c)",                                      "suspicious-semicolon" },  // clang-tidy bugprone-suspicious-semicolon (post-filtered below)
            // S6-A new checks:
            { "(type_definition declarator: (type_identifier) @c)",                                         "typedef-over-using" },    // C-style typedef struct/union in C++ — prefer using T = ...
            { "(number_literal) @c",                                                                        "magic-number" },          // numeric literal outside const/constexpr init (post-filtered below)
            { "(catch_clause body: (compound_statement) @c)",                                               "empty-catch" },           // catch block with empty/comment-only body (post-filtered below)
            { "(assignment_expression left: (_) @lhs right: (_) @rhs (#eq? @lhs @rhs))",                   "self-assign" },           // x = x — predicate rejects unequal pairs before post-filtering
        };
        // §P0.2: kLintMaxPerRule (lintrules.h) is spent PER RULE, not pooled — a rule can only ever be capped
        // by its own matches. A rule that lands exactly on the budget has a count= that is a FLOOR, disclosed below.
        // The corpus text the one grouped walk read, kept alive for the symbol-level passes below so they
        // do not re-open the same files a second and third time. Lives exactly as long as this lint block.
        std::vector<std::string>           corpusBytes;
        std::vector<std::vector<AstMatch>> grouped = builtInLintCaptures( ing, checks, corpusBytes );
        ms = std::move( grouped[0] );
        for( const AstQuerySpec& check : checks )       // saturation is measured on the RAW captures, before the post-filters below thin them
        {
            std::size_t rawForRule = 0;
            for( const AstMatch& m : ms )
            {
                if( m.tag == check.tag )
                {
                    ++rawForRule;
                }
            }
            if( rawForRule >= kLintMaxPerRule )
            {
                saturatedRules.push_back( { check.tag, false } );
            }
        }

        // suspicious-semicolon: the query also matches a normal `if(x) foo();` (the grammar gives both an
        // expression_statement consequence). Keep ONLY an empty body — matched text trims to just ";" — the real bug.
        ms.erase( std::remove_if( ms.begin(), ms.end(), []( const AstMatch& m )
                                  {
                                      if( m.tag != "suspicious-semicolon" )
                                      {
                                          return false;
                                      }
                                      const auto ws = []( char c )
                                      { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };
                                      std::string_view t  = m.text;
                                      while( !t.empty() && ws( t.front() ) )
                                      {
                                          t.remove_prefix( 1 );
                                      }
                                      while( !t.empty() && ws( t.back() ) )
                                      {
                                          t.remove_suffix( 1 );
                                      }
                                      return t != ";";   // non-empty body → not the bug → drop
                                  } ),
                  ms.end() );

        // empty-catch: keep ONLY catch bodies whose trimmed text is empty (nothing but whitespace/braces).
        // The captured node is the compound_statement — its text is "{...}"; trim and check for "{}".
        ms.erase( std::remove_if( ms.begin(), ms.end(), []( const AstMatch& m )
                                  {
                                      if( m.tag != "empty-catch" )
                                      {
                                          return false;
                                      }
                                      const auto ws = []( char c )
                                      { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };
                                      std::string_view t = m.text;
                                      while( !t.empty() && ws( t.front() ) )
                                      {
                                          t.remove_prefix( 1 );
                                      }
                                      while( !t.empty() && ws( t.back() ) )
                                      {
                                          t.remove_suffix( 1 );
                                      }
                                      // After trimming, an empty body is "{}" or "{ }" (only whitespace between braces).
                                      if( t.size() < 2 || t.front() != '{' || t.back() != '}' )
                                      {
                                          return true; // malformed — drop
                                      }
                                      std::string_view inner = t.substr( 1, t.size() - 2 );
                                      for( char c : inner )
                                      {
                                          if( !ws( c ) )
                                          {
                                              return true; // non-whitespace inside → not empty → drop
                                          }
                                      }
                                      return false;   // truly empty catch body → keep the finding
                                  } ),
                  ms.end() );

        std::vector<std::string> magicFileBytes( ing.files.size() );
        std::vector<char>        magicFileRead( ing.files.size(), 0 );
        const auto magicBytes = [ & ]( std::uint32_t fileId ) -> const std::string&
        {
            if( !magicFileRead[fileId] )
            {
                darkflags::readWhole( diskPath( ing, fileId ), magicFileBytes[fileId] );
                magicFileRead[fileId] = 1;
            }
            return magicFileBytes[fileId];
        };

        // magic-number: drop literals that are:
        //   (a) semantic -2..2 forms (universal idioms) or base-prefixed masks/protocol constants
        //   (b) inside a const/constexpr variable initializer (that's exactly the right place for numbers)
        //   (c) inside an enum body (enumerator values are naturally numeric)
        // Keep only literals inside function/method bodies to limit noise.
        // The enclosing symbol check (Function/Method) is the main guard.
        ms.erase( std::remove_if( ms.begin(), ms.end(), [ & ]( const AstMatch& m )
                                  {
                                      if( m.tag != "magic-number" )
                                      {
                                          return false;
                                      }
                                      if( isUniversalOrAllowlistedNumber( m.text ) )
                                      {
                                          return true;
                                      }
                                      const std::string& src = magicBytes( m.fileId );
                                      if( !src.empty() && isConstantInitializerNumber( src, m.startByte ) )
                                      {
                                          return true;
                                      }
                                      // must be inside a function/method body to be a magic-number finding
                                      const Symbol* e = enclosing( m.fileId, m.startByte );
                                      if( !e || ( e->kind != SymKind::Function && e->kind != SymKind::Method ) )
                                      {
                                          return true;
                                      }
                                      return false;   // non-trivial literal in a function body → flag it
                                  } ),
                  ms.end() );

        // #eq? rejected unequal assignment pairs inside tree-sitter, so the remaining captures arrive as
        // lhs/rhs twins in byte order. Collapse every complete twin pair into one finding; unlike the old
        // (file,line) bucket this cannot cross-wire two independent assignments sharing a source line.
        {
            std::vector<AstMatch> saKeep;
            std::vector<AstMatch> saCaptured;
            for( const AstMatch& m : ms )
            {
                if( m.tag == "self-assign" )
                {
                    saCaptured.push_back( m );
                }
            }
            ms.erase( std::remove_if( ms.begin(), ms.end(), []( const AstMatch& m ) { return m.tag == "self-assign"; } ), ms.end() );
            for( std::size_t i = 0; i + 1 < saCaptured.size(); i += 2 )
            {
                const AstMatch& lhs = saCaptured[i];
                const AstMatch& rhs = saCaptured[i + 1];
                if( lhs.fileId != rhs.fileId || lhs.text != rhs.text )
                {
                    continue; // defensive: an incomplete/crossed capture pair is never evidence
                }
                const auto trim = []( std::string_view t ) -> std::string
                {
                    const auto ws = []( char c ) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };
                    while( !t.empty() && ws( t.front() ) )
                    {
                        t.remove_prefix( 1 );
                    }
                    while( !t.empty() && ws( t.back() ) )
                    {
                        t.remove_suffix( 1 );
                    }
                    return std::string( t );
                };
                const std::string expression = trim( lhs.text );
                AstMatch hit;
                hit.fileId    = lhs.fileId;
                hit.startByte = lhs.startByte;
                hit.endByte   = lhs.endByte;
                hit.line      = lhs.line;
                hit.tag       = "self-assign";
                hit.text      = expression + " = " + expression;
                saKeep.push_back( std::move( hit ) );
            }
            // Sort saKeep for determinism before appending.
            std::sort( saKeep.begin(), saKeep.end(), [ & ]( const AstMatch& x, const AstMatch& y )
                       {
                if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
                return x.line < y.line; } );
            for( auto& hit : saKeep )
            {
                ms.push_back( std::move( hit ) );
            }
        }

        // Symbol-level checks (S6-A): walk each Function/Method body — checks that need line-counting or
        // control-flow nesting depth, which a single tree-sitter @capture can't give without reparsing.
        // These produce AstMatch entries (same format) so they flow into the same XML tally/listing.
        //
        //   large-function    — body line-span (newlines in [sigEndByte, endByte)) > 80
        //   deep-nesting      — curly-brace nesting depth inside [sigEndByte, endByte) > 4
        //   inconsistent-return — mix of `return;` and `return <expr>;` in the same body
        //
        // Note: deep-nesting uses curly-brace depth as a proxy for control-flow depth (fast, no full reparse).
        // This correctly catches deeply nested if/for/while blocks because each adds a `{` in Allman/K&R style.
        // It can over-report on struct-initialiser nesting — acceptable, as those are also a complexity signal.
        { PROFILE_SCOPE_DESCRIBE( "lint: lintSymbolLevelChecks" );
        for( AstMatch& symHit : lintSymbolLevelChecks( ing, &corpusBytes ) )
        {
            ms.push_back( std::move( symHit ) );
        }
        }

        // unreachable-code (joern-lite CFG sketch): pure-syntactic intra-block dead-code — a statement
        // after an unconditional exit (return/break/continue/throw, +Python raise) in the SAME block.
        // Conservative: no dataflow, goto excluded, jump-target siblings stop the scan (no false positives
        // on code reached via a label or on `if(x) return; foo();` where foo() is a reachable sibling).
        // Already collected, sorted and capped: it rode the one grouped walk above as grouped[3] instead of
        // spending a fourth read + parse of the whole corpus on its own pool.
        {
            PROFILE_SCOPE_DESCRIBE( "lint: mergeUnreachable" );
            for( auto& h : grouped[3] )
            {
                ms.push_back( std::move( h ) );
            }
        }

        // The packs that live outside this function: the atoms-of-confusion pack (src/atoms.h), the
        // identifier-naming lens (src/naminglens.h) and the cache-friendliness pack (src/cachelint.h).
        // Each merges its own findings, its own floor disclosures and — for the packs whose rule list is
        // owned by the pack — its own rule names. All run here, inside the one --lint guard, so the sort
        // below covers every built-in finding regardless of its source.
        { PROFILE_SCOPE_DESCRIBE( "lint: mergeAtomsPack" ); mergeAtomsPack( ing, ms, saturatedRules, allRuleNames, std::move( grouped[1] ) ); }
        { PROFILE_SCOPE_DESCRIBE( "lint: mergeNamingLens" ); mergeNamingLens( ing, ms, saturatedRules, cfg.namingLocals, &corpusBytes ); }
        { PROFILE_SCOPE_DESCRIBE( "lint: mergeCachePack" ); mergeCachePack( ing, ms, saturatedRules, allRuleNames, std::move( grouped[2] ) ); }

        // Re-sort the combined findings (AST + symbol-level) for deterministic output.
        std::sort( ms.begin(), ms.end(), [ & ]( const AstMatch& x, const AstMatch& y )
                   {
            if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
            if( x.startByte != y.startByte ) { return x.startByte < y.startByte;
}
            return x.tag < y.tag; } );
        }   // if( cfg.lint ) — built-in checks

        // LintOut = the unified finding shape so built-in tags and user rule ids emit identically (defined
        // at file scope, above lintSymbolLevelChecks — dedupeLintFindings shares it). sev is empty for
        // built-ins (facts, not severities); user findings carry their declared sev=.
        std::vector<LintOut> outs;  outs.reserve( ms.size() );
        for( const AstMatch& m : ms )
        {
            outs.push_back( { m.fileId, m.startByte, m.line, m.tag, std::string(), m.text } );
        }

        // --lint-rules=DIR: load user YAML rules and run them through the SAME astQuery engine. Malformed
        // files alert+skip inside the loader; a bad ts query alert+skips inside astQuery. Exit 1 ONLY if the
        // flag was given but zero rules loaded (nothing to run = a user mistake worth surfacing).
        std::vector<LintRule>    userRules;
        std::vector<std::string> uncompiledUserRuleIds;   // §L10: main query compiled for NO grammar
        if( !cfg.lintRulesDir.empty() )
        {
            userRules = loadLintRules( std::string( cfg.lintRulesDir ) );
            if( userRules.empty() )
            {
                std::print( stderr, "ripwire: --lint-rules={}: no rules loaded\n", cfg.lintRulesDir );
                return 1;
            }
            const auto [ userFindings, saturatedUserRuleIds, uncompiledIds ] = runLintRules( ing, userRules );
            for( const LintFinding& f : userFindings )
            {
                outs.push_back( { f.fileId, f.startByte, f.line, f.id, f.severity, f.message } );
            }
            for( const std::string& id : saturatedUserRuleIds )
            {
                saturatedRules.push_back( { id, true } );
            }
            uncompiledUserRuleIds = uncompiledIds;
        }

        // --lint-select=PREFIX[,...] / --lint-ignore=PREFIX[,...]: resolved HERE, not in validateConfig,
        // because a PREFIX can legitimately name a user rule id that --lint-rules=DIR has only just
        // loaded above. See resolveLintSelection's own header for the pool it validates against.
        const std::optional<rw::lintcatalog::LintSelection> lintSelOpt = resolveLintSelection( cfg, userRules );
        if( !lintSelOpt )
        {
            return 1;   // refusal already printed
        }
        const rw::lintcatalog::LintSelection& lintSel = *lintSelOpt;
        if( lintSel.active )
        {
            outs.erase( std::remove_if( outs.begin(), outs.end(),
                                        [ & ]( const LintOut& o ) { return !rw::lintcatalog::lintSelectionKeeps( lintSel, o.rule ); } ),
                       outs.end() );
        }

        // Final deterministic order over the COMBINED set — see sortLintRows for why the key runs all the
        // way out to the row's own text.
        sortLintRows( ing, outs );

        // §P6.1: collapse rows that would render byte-identically (see dedupeLintFindings above for why —
        // two genuinely different AST captures, e.g. the same magic-number value spelled twice on one line,
        // can share the same rule/file:line/enclosing-symbol/text because the row carries no column).
        outs = dedupeLintFindings( ing, std::move( outs ) );

        // W3-S (2026-08-19): E6 found --lint emitting an UNCAPPED payload on a large corpus — 2,037,645 B /
        // 6,169 findings (~330 B/finding, driven by long single-line minified text=) with no --help promise
        // ("trims to fit") kept and no way for a caller to see it coming; every other verb in the catalog has
        // a display default (--hotspots 40, --grep 100, …), --lint alone had none. Measured HERE before
        // choosing the cap: this repo prints 367,924 B / 3,213 findings (~114 B/finding); a second, larger
        // polyglot fixture (ctxpack, 1,033 tracked files) prints 254,445 B / 2,312 findings (~110 B/finding).
        // kLintDefaultPayloadBytes=100,000 lands an order of magnitude under E6's pathological case while
        // staying multiples of every other capped verb's default payload on this repo (--hotspots ~5.5 KB,
        // --clones ~17 KB, --grep(100 hits) ~57 KB) — --lint's own facts are individually smaller so it earns
        // a bigger budget. An explicit --limit=N always beats it (effectiveRowCap's existing rule), so a
        // caller who already knew to page past a cap sees no change.
        static constexpr std::size_t kLintDefaultPayloadBytes = 100000;
        const bool paging = cfg.pageLimit > 0 || cfg.pageOffset > 0;
        std::size_t lintDefaultShown = outs.size();
        if( !paging )
        {
            // Byte-budget the default (unpaged) run. Rows are already in final sorted order, so this keeps
            // the same sorted PREFIX pageWindow() would keep by row count; the stopping rule is bytes here
            // because a corpus with long text= rows (E6's vendored-bundle case) needs far FEWER rows to reach
            // the same budget than a corpus of short rows does. text= dominates real row size and is summed
            // exactly; the flat +80 covers the <f> tag markup, path, rule name and enclosing symbol name,
            // which are all short in practice — an estimate, not a second full render (that would mean
            // rendering the very tail this exists to avoid paying for), and one that can only ever be
            // conservative in the wrong direction (undercounting an unusually long path/rule name by a few
            // dozen bytes), never by the orders of magnitude that would silently readmit the 2 MB case.
            std::size_t bytesUsed = 0;
            lintDefaultShown = 0;
            for( std::size_t i = 0; i < outs.size(); ++i )
            {
                const LintOut& m = outs[i];
                const Symbol*  e = enclosing( m.fileId, m.startByte );
                const std::size_t rowBytes = m.text.size() + m.rule.size() + m.sev.size()
                                            + ing.files[ m.fileId ].size()
                                            + ( e ? e->name.size() : 0 ) + 80;
                if( lintDefaultShown > 0 && bytesUsed + rowBytes > kLintDefaultPayloadBytes )
                {
                    break;   // the sorted prefix already kept at least one row — stop BEFORE the overflow row
                }
                bytesUsed += rowBytes;
                ++lintDefaultShown;
            }
        }
        const PageWindow lintPage = paging
                                  ? pageWindow( outs.size(), cfg.pageLimit, cfg.pageOffset )
                                  : PageWindow{ 0, lintDefaultShown };
        const std::size_t shownCount = lintPage.end - lintPage.begin;

        // §P0.2 disclosure: which rules (if any) spent their whole per-rule budget, so their count= is a floor.
        const auto capOf = [ & ]( const std::string& ruleName, bool isUserRule ) -> const RuleCap*
        {
            for( const RuleCap& rc : saturatedRules )
            {
                if( rc.rule == ruleName && rc.isUserRule == isUserRule )
                {
                    return &rc;
                }
            }
            return nullptr;
        };
        // H8 (capture-audit 2026-09-04, lens 1 F5): OR over the rules this document EMITS, never over every
        // rule that saturated. `--lint-select=cache-` used to inherit findings_capped="1" from the UNSELECTED
        // magic-number rule, so 398 had to be read as a floor when, by the legend's own definition, it was a
        // total. Same predicate as the tally-row loop below and the SARIF twin (lintRuleEmitted).
        const auto lintRuleEmitted = [ & ]( const RuleCap& rc ) -> bool
        {
            return !lintSel.active || rw::lintcatalog::lintSelectionKeeps( lintSel, rc.rule );
        };
        const bool anyRuleCapped = std::any_of( saturatedRules.begin(), saturatedRules.end(), lintRuleEmitted );

        // §L7: per-rule LANGUAGE applicability — a rule whose registered languages (lintcatalog.h) never
        // intersect the corpus' own languages is not "measured zero", it is structurally inert here.
        // Applicability is per-LANGUAGE granularity (does the corpus contain ANY file of a language this
        // rule's grammar could ever satisfy), never per-file-content — a rule can be "applicable" and
        // still find nothing. See computeLintApplicability's own header for why it lives outside this function.
        const LintApplicability lintApplicability = computeLintApplicability( ing, cfg.lint, allRuleNames, userRules, lintSel );
        const std::uint32_t     corpusLangs        = lintApplicability.corpusLangs;
        const std::size_t       inertRuleCount      = lintApplicability.inertRuleCount;

        // --sarif: `outs` re-serialized as SARIF instead of the native XML below (emitRunLintSarif above).
        // validateConfig already refused this alongside --match / --with-profile / paging.
        if( cfg.sarif )
        {
            emitRunLintSarif( d, allRuleNames, userRules, saturatedRules, outs, lintSel, corpusLangs, enclosing );
            return 0;
        }

        // --with-profile join, lifted into buildHeatAnnotations (runLint was already the file's largest
        // verb): per-finding heat_* attribute strings index-aligned with `outs`, + the root attribute.
        std::vector<std::string> heatByFinding;
        std::string              heatJoinedAttr;
        if( !cfg.withProfile.empty() )
        {
            auto heat = buildHeatAnnotations( cfg.withProfile, ing, outs, enclosing );
            if( !heat )
            {
                return 1;   // refusal already printed — never join nothing silently
            }
            heatByFinding  = std::move( heat->first );
            heatJoinedAttr = std::move( heat->second );
        }

        // §L7 root disclosure: inert_rules= (only when >0 — same "absent = nothing to say" convention as
        // findings_capped=) and, only when --lint-select/--lint-ignore were given, selected="K of N" plus
        // the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one.
        std::string lintRootExtra;
        if( inertRuleCount > 0 )
        {
            lintRootExtra += std::format( " inert_rules=\"{}\"", inertRuleCount );
        }
        if( lintSel.active )
        {
            lintRootExtra += std::format( " selected=\"{} of {}\"", lintSel.selectedCount, lintSel.totalCount );
            if( !cfg.lintSelect.empty() )
            {
                lintRootExtra += " select=\"" + ex( cfg.lintSelect ) + "\"";
            }
            if( !cfg.lintIgnore.empty() )
            {
                lintRootExtra += " ignore=\"" + ex( cfg.lintIgnore ) + "\"";
            }
        }
        // capture-audit 2026-09-04 (M16): a modifier's effect is stamped on the root the way --lint-select's
        // selected=/select= is — `--lint --naming-locals` moved the count 3717 -> 4898 on this repo with no
        // attribute saying why. Absent when the modifier is off (absent = nothing to say, as with inert_rules=).
        if( cfg.namingLocals )
        {
            lintRootExtra += " naming_locals=\"1\"";
        }

        // §P8 collision, documented not renamed — see the --grep legend above for the full reasoning.
        std::print( "<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; "
                    "in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). "
                    "A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. "
                    "Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. "
                    "A rule that spends its whole budget carries count_capped=\"1\" — its count= is then a FLOOR (that rule's raw captures reached the "
                    "per-rule budget; only its own matches can cap it); findings_capped=\"1\" on the root ⇒ at least one PRINTED rule row is a "
                    "floor (never inherited from a rule lint-select/lint-ignore dropped), and the root then also carries counts_floor=\"1\" "
                    "and capped=\"1\": findings= and total= are floors, rows exist that no page holds. "
                    "Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). "
                    "On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed "
                    "them, absent an explicit limit=) — a different fact from the per-rule count_capped=\"1\" above, which is a MATCH-BUDGET "
                    "floor on one rule's own count=; findings= is the true total unless findings_capped=\"1\" floors it. "
                    "A rule row's applicable=\"0\" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this "
                    "corpus at all — its count=\"0\" is structural inertness, never a measurement; the root's inert_rules=N tallies "
                    "how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a "
                    "family (e.g. cache-); the root then carries selected=\"K of N\" plus the raw select=/ignore= you passed. "
                    "naming_locals=\"1\" on the root ⇒ the opt-in naming-locals modifier was on (the naming-* rules also read local "
                    "variables inside already-flagged functions); absent ⇒ off, and the naming-* counts cover declarations only. "
                    "Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window "
                    "(the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the "
                    "cut carries shown_rows=\"0\" rows_capped=\"1\" while its count= stays the true total — never confuse a capped-away "
                    "rule with one that measured zero); this is a DIFFERENT fact from the row's own count_capped=\"1\" above (that rule's "
                    "own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. "
                    "A lint-rules row's compiled=\"0\" ⇒ that rule's tree-sitter QUERY failed to compile for every linked grammar (a "
                    "malformed or misspelled pattern) — its count=\"0\" never ran at all, a different claim from applicable=\"0\" above "
                    "(a well-formed query whose declared language just is not in this corpus) and from an ordinary count=\"0\" (a "
                    "well-formed query that ran and found nothing); absent ⇒ the query compiled. -->" );
        if( !cfg.withProfile.empty() )
        {
            std::print( "<!-- with-profile: heat_* on a finding = MEASURED inclusive totals of the joined #PROF_TSV scope — the nearest "
                        "PROFILE_SCOPE site at/above the finding inside its own enclosing symbol. Columns are whatever counter tier the "
                        "profiled run armed; an ABSENT heat column was not measured, never zero. heat_joined= on the root counts annotated "
                        "findings; 0 is honest (no finding sits inside a profiled scope), never an error. -->" );
        }
        {
            // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY, rule 3): --lint ESTABLISHED the
            // six-attribute paging block that pageDisclosure() now serves to every other paging verb, but its
            // own hand-rolled copy never grew the capped= bit pageDisclosure emits, so the verb that defined
            // the shape was the one verb that did not spell it — fixed here by calling the shared helper
            // instead of hand-rolling a second copy (W3-S: this is also what lets the new default byte cap
            // above disclose shown=/capped= on the UNPAGED path, which the old hand-rolled `else` branch could
            // not do at all). discloseCap=true unconditionally, same as every other default-capped verb
            // (--impact, --hotspots, …): pageDisclosure only adds the paging half (total=/has_more=/
            // next_offset=/offset=/limit=) when --limit/--offset was actually given, so an un-paged, un-capped
            // run (a small corpus under kLintDefaultPayloadBytes) is byte-identical to before this change.
            // Distinct from findings_capped= below, which is rule 4's FLOOR marker on the total itself.
            char lintPageBuf[ kPageDisclosureCap ];
            std::print( "<lint findings=\"{}\"{}{}{}{}{}>", outs.size(),
                        pageDisclosure( lintPageBuf, sizeof( lintPageBuf ), shownCount, outs.size(), lintPage.end,
                                       cfg.pageLimit, cfg.pageOffset, /*discloseCap=*/true, kXmlPageSyntax,
                                       /*collectionCapped=*/ anyRuleCapped ),   // H8: a floored rule floors findings=
                        anyRuleCapped ? " findings_capped=\"1\"" : "", heatJoinedAttr, lintRootExtra, lintRootAttr );
        }
        if( cfg.lint )
        { // built-in per-rule tally (order → deterministic)
            for( const std::string& rn : allRuleNames )
            {
                if( lintSel.active && !rw::lintcatalog::lintSelectionKeeps( lintSel, rn ) )
                { // deselected — no row at all, so it can never look like a checked-and-empty rule
                    continue;
                }
                const RuleTally rt = tallyLintRule( outs, rn, /*wantSevEmpty=*/true, lintPage );
                const rw::lintcatalog::LintCatalogRow* catRow = rw::lintcatalog::lintCatalogFind( rn );
                const bool applicable = catRow == nullptr || ( catRow->langMask & corpusLangs ) != 0;
                printLintRuleTallyRow( rn, nullptr, rt.count, rt.shown, capOf( rn, false ) != nullptr, applicable );
            }
        }
        for( const LintRule& r : userRules )                          // user per-rule tally (declaration order → deterministic)
        {
            if( lintSel.active && !rw::lintcatalog::lintSelectionKeeps( lintSel, r.id ) )
            {
                continue;
            }
            const RuleTally rt = tallyLintRule( outs, r.id, /*wantSevEmpty=*/false, lintPage );
            const bool  applicable = ( rw::langBit( r.lang ) & corpusLangs ) != 0;
            const bool  compiled   = std::find( uncompiledUserRuleIds.begin(), uncompiledUserRuleIds.end(), r.id ) == uncompiledUserRuleIds.end();
            const std::string sevEx = ex( r.severity );
            printLintRuleTallyRow( ex( r.id ), &sevEx, rt.count, rt.shown, capOf( r.id, true ) != nullptr, applicable, compiled );
        }
        for( std::size_t findingIndex = lintPage.begin; findingIndex < lintPage.end; ++findingIndex )
        {
            const LintOut&          m  = outs[ findingIndex ];
            const Symbol*           e  = enclosing( m.fileId, m.startByte );
            const std::string_view  rp = lintSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ m.fileId ], lintRootPrefix ) : std::string_view( ing.files[ m.fileId ] );
            if( m.sev.empty() )
            { // built-in finding — unchanged shape (no sev=)
                std::print( "<f rule=\"{}\" p=\"{}:{}\" in=\"{}\"{}>", ex( m.rule ), ex( rp ), m.line, e ? ex( e->name ) : "",
                            heatByFinding.empty() ? std::string() : heatByFinding[ findingIndex ] );
            }
            else
            { // user finding — carries sev=
                std::print( "<f rule=\"{}\" sev=\"{}\" p=\"{}:{}\" in=\"{}\"{}>", ex( m.rule ), ex( m.sev ), ex( rp ), m.line, e ? ex( e->name ) : "",
                            heatByFinding.empty() ? std::string() : heatByFinding[ findingIndex ] );
            }
            emitEscaped( m.text );
            std::print( "</f>" );
        }
        std::print( "</lint>" );
        return 0;
    }
    return std::nullopt;
}

}   // namespace — verbs_lint.h section of main.cpp
