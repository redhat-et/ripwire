#pragma once
// ingest_lexical.h — a SECTION of ingest.cpp (see the RIPWIRE_INGEST_TU note there), not a library header.
//
// NO-SKIP-INGEST (owner 2026-11-14: "why are we skipping files? ... we should not be skipping files"). Every crawled
// file is indexed. When a full parse cannot or should not run — the file is over --max-file-size, its parse ran past
// the parse budget, or it is a .json/.yml/.yaml past its full-index ceiling — the parse worker indexes it LEXICALLY
// here instead, and records how on its FileHealth (indexMode / keysCut, model.h FileIndexMode):
//   * code: a definition is a line SHAPED like one (crossref.h definitionShaped, the same reading whereis' lexical
//     labels and degradedscan use — one reading, not a second), a call is `name(` outside comments and strings. A
//     definition's span runs to the next definition, so the calls between them attribute to it. No complexity, no
//     clone key, no binding: what a parse would add is disclosed as missing, not guessed;
//   * data: the top- and second-level keys the json/yaml tags queries take (queries/json|yaml/tags.scm), read
//     without a parse, at most kDataFileKeyCap of them (RIPWIRE_DATA_KEYS raises it); the rest are counted in keysCut.
// Both readers are linear in the file's bytes and bounded per line, so they are the budget's floor, never its risk.

#ifndef RIPWIRE_INGEST_TU
#error "ingest_lexical.h is a section of ingest.cpp — include it only from there"
#endif

namespace rw
{
namespace
{

// A line longer than this is not tested for a definition shape (minified or generated text: definitionShaped's
// per-name cost is linear in the line), and at most this many names per line are tested. Calls are still read.
inline constexpr std::size_t   kLexicalDefLineBytes      = 2048;
inline constexpr std::uint32_t kLexicalDefTestsPerLine   = 8;
inline constexpr std::uint32_t kLexicalNamesPerLine      = 512;

// Words that open a parenthesis without naming a callee or a definition: control flow and operators in the indexed
// languages. A name in this list is neither a lexical call nor a lexical definition.
inline constexpr std::string_view kLexicalNotCallees[] = {
    "if", "for", "while", "switch", "catch", "return", "sizeof", "else", "do", "try", "elif", "with", "assert", "match",
    "loop", "foreach", "lock", "fixed", "typeof", "defined", "alignof", "alignas", "decltype", "static_assert", "new",
    "delete", "throw", "yield", "await", "case", "until", "unless", "when", "not", "and", "or", "in", "is", "function",
    "fn", "def", "func", "fun", "lambda", "super", "this", "self", "import", "require", "export", "from", "as", "let",
    "var", "const", "static", "async", "goto", "noexcept", "operator", "template", "typename", "using", "namespace",
    "class", "struct", "enum", "union", "interface", "trait", "impl", "extension", "protocol", "type", "typedef", "go",
    "defer", "select", "elsif", "except", "finally", "raise", "print", "exec", "where", "keyof", "instanceof", "void",
};

inline bool lexicalNotCallee( std::string_view name ) noexcept
{
    return std::ranges::find( kLexicalNotCallees, name ) != std::end( kLexicalNotCallees );
}

// The declaration word directly before a lexical definition's name → its kind. A namespace / impl / extension block
// is a scope, not a symbol: no definition (nullopt). Anything else shaped like a definition is a function.
inline std::optional<SymKind> lexicalDefKind( std::string_view prior, bool isDefine ) noexcept
{
    struct KeywordKind
    {
        std::string_view       keyword;
        std::optional<SymKind> kind;   // nullopt: a scope opener (namespace, impl, …), not a definition of its own
    };
    static constexpr KeywordKind kKeywordKinds[] =
    {
        { "class", SymKind::Class },          { "enum", SymKind::Class },          { "struct", SymKind::Struct },
        { "union", SymKind::Struct },         { "interface", SymKind::Interface }, { "trait", SymKind::Interface },
        { "protocol", SymKind::Interface },   { "type", SymKind::NamedType },      { "typedef", SymKind::NamedType },
        { "using", SymKind::NamedType },      { "namespace", std::nullopt },       { "impl", std::nullopt },
        { "extension", std::nullopt },        { "module", std::nullopt },
    };
    if( isDefine )
    {
        return SymKind::Macro;
    }
    const auto* hit = std::ranges::find( kKeywordKinds, prior, &KeywordKind::keyword );
    return hit != std::end( kKeywordKinds ) ? hit->kind : std::optional<SymKind>( SymKind::Function );
}

// One line's names outside comments and string literals, in order. `inBlock` carries a /* … */ comment across lines;
// string state does not cross a newline (a mis-read quote costs the rest of one line, never the file).
struct LexicalLineScan
{
    bool hashComments = false;   // `#` opens a line comment (Python, Ruby, shell, …); else `//` and `/* */`
    bool singleQuotes = true;    // `'` opens a string (false for Rust, whose lifetimes are `'a`)
    bool inBlock      = false;
    std::vector<std::pair<std::uint32_t, std::uint32_t>> names;   // (offset in line, length)

    void scan( std::string_view line )
    {
        names.clear();
        std::size_t i     = 0;
        char        quote = 0;
        while( i < line.size() && names.size() < kLexicalNamesPerLine )
        {
            const char c    = line[ i ];
            const char next = i + 1 < line.size() ? line[ i + 1 ] : '\0';
            if( inBlock )
            {
                const std::size_t close = line.find( "*/", i );
                if( close == std::string_view::npos )
                {
                    return;
                }
                inBlock = false;
                i       = close + 2;
                continue;
            }
            if( quote != 0 )
            {
                i += ( c == '\\' ) ? 2 : 1;
                quote = ( c == quote ) ? 0 : quote;
                continue;
            }
            if( c == '"' || c == '`' || ( c == '\'' && singleQuotes ) )
            {
                quote = c;
                ++i;
                continue;
            }
            if( hashComments ? c == '#' : ( c == '/' && next == '/' ) )
            {
                return;
            }
            if( !hashComments && c == '/' && next == '*' )
            {
                inBlock = true;
                i += 2;
                continue;
            }
            if( crossref::isIdentByte( (unsigned char)c ) )
            {
                std::size_t j = i;
                while( j < line.size() && crossref::isIdentByte( (unsigned char)line[ j ] ) )
                {
                    ++j;
                }
                if( !std::isdigit( (unsigned char)c ) )
                {
                    names.emplace_back( std::uint32_t( i ), std::uint32_t( j - i ) );
                }
                i = j;
                continue;
            }
            ++i;
        }
    }
};

inline bool opensParenAfter( std::string_view line, std::size_t end ) noexcept
{
    const std::string_view rest = line.substr( std::min( end, line.size() ) );
    const auto             next = std::ranges::find_if( rest, []( char c ) { return c != ' ' && c != '\t'; } );
    return next != rest.end() && *next == '(';
}

// A quote that opens a literal in the lexical scan: everywhere but Rust, whose ' also starts a lifetime.
inline constexpr bool singleQuotesDelimitLiterals( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Rust: return false;
        default:         return true;
    }
}

// The code reader. Appends this file's lexical definitions and calls; returns nothing (the mode is the caller's).
inline void extractLexicalCode( std::uint32_t fileId, Lang lang, std::string_view bytes, std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    LexicalLineScan scan;
    scan.hashComments = usesHashLineComments( lang );
    scan.singleQuotes = singleQuotesDelimitLiterals( lang );
    const std::size_t firstDef = defs.size();
    std::uint32_t     lineNo   = 0;
    for( std::size_t lineStart = 0; lineStart < bytes.size(); )
    {
        std::size_t lineEnd = bytes.find( '\n', lineStart );
        lineEnd             = lineEnd == std::string_view::npos ? bytes.size() : lineEnd;
        const std::string_view line = bytes.substr( lineStart, lineEnd - lineStart );
        ++lineNo;
        scan.scan( line );
        const bool    defLine  = line.size() <= kLexicalDefLineBytes;
        const std::size_t firstByte = line.find_first_not_of( " \t" );
        const bool    isDefine = firstByte != std::string_view::npos && line[ firstByte ] == '#';   // a preprocessor line: test its names
        std::uint32_t defTests = 0;
        std::string_view prior;
        for( const auto& [ at, len ] : scan.names )
        {
            const std::string_view name   = line.substr( at, len );
            const bool             call   = opensParenAfter( line, at + len );
            const std::string_view before = prior;
            prior                         = name;
            if( lexicalNotCallee( name ) )
            {
                continue;
            }
            const bool markerBefore = !before.empty() && std::ranges::find( kLexicalNotCallees, before ) != std::end( kLexicalNotCallees );
            if( defLine && ( call || markerBefore || isDefine ) && defTests < kLexicalDefTestsPerLine )
            {
                ++defTests;
                if( crossref::definitionShaped( line, name, at ) )
                {
                    if( const std::optional<SymKind> kind = lexicalDefKind( before, crossref::definesNameAt( line, at ) ) )
                    {
                        RawDef d;
                        d.fileId    = fileId;
                        d.line      = lineNo;
                        d.startByte = std::uint32_t( lineStart );
                        d.nameByte  = std::uint32_t( lineStart + at );
                        d.kind      = *kind;
                        d.lang      = lang;
                        d.name      = std::string( name );
                        defs.push_back( std::move( d ) );
                    }
                    continue;
                }
            }
            if( call )
            {
                RawRef r;
                r.fileId    = fileId;
                r.startByte = std::uint32_t( lineStart + at );
                r.line      = lineNo;
                r.lang      = lang;
                r.role      = RefRole::Call;
                r.memberCall = at > 0 && line[ at - 1 ] == '.';
                r.name      = name;
                refs.push_back( std::move( r ) );
            }
        }
        lineStart = lineEnd + 1;
    }
    // A definition's span runs to the next one (the file's end for the last): the calls between attribute to it. The
    // signature is the whole span (bodyByte = endByte), so no clone key and no body metric is read from a guess.
    for( std::size_t i = firstDef; i < defs.size(); ++i )
    {
        RawDef& d       = defs[ i ];
        const bool last = i + 1 == defs.size();
        d.endByte       = last ? std::uint32_t( bytes.size() ) : std::max( defs[ i + 1 ].startByte, d.nameByte + 1 );
        d.bodyByte      = d.endByte;
        const std::uint32_t endLine = last ? lineNo : std::max( defs[ i + 1 ].line, d.line );
        d.loc           = endLine - d.line + 1;
    }
}

// The data key cap, RIPWIRE_DATA_KEYS=<n> raising it (read once; 0 or unparseable keeps kDataFileKeyCap).
inline std::uint32_t dataFileKeyCap()
{
    static const std::uint32_t cap = []
    {
        const char*         env = std::getenv( "RIPWIRE_DATA_KEYS" );
        const unsigned long v   = env != nullptr ? std::strtoul( env, nullptr, 10 ) : 0ul;
        return v > 0 && v <= 0xFFFFFFFFul ? std::uint32_t( v ) : kDataFileKeyCap;
    }();
    return cap;
}

// One key the data readers found: kept as a Section definition while under the cap, counted past it.
struct DataKeySink
{
    std::uint32_t        fileId;
    Lang                 lang;
    std::vector<RawDef>& defs;
    std::uint32_t        cap;
    std::uint32_t        kept = 0;
    std::uint32_t        cut  = 0;

    void key( std::string_view name, std::uint32_t line, std::uint32_t startByte, std::uint32_t endByte )
    {
        if( name.empty() )
        {
            return;
        }
        if( kept >= cap )
        {
            ++cut;
            return;
        }
        ++kept;
        RawDef d;
        d.fileId    = fileId;
        d.line      = line;
        d.startByte = startByte;
        d.nameByte  = startByte;
        d.endByte   = std::max( endByte, startByte + 1 );
        d.bodyByte  = d.endByte;
        d.loc       = 1;
        d.kind      = SymKind::Section;
        d.lang      = lang;
        d.name      = std::string( name );
        defs.push_back( std::move( d ) );
    }
};

// JSON: a string followed by `:` directly inside the root object (top level) or inside an object that is a top-level
// key's value (second level) — the two shapes queries/json/tags.scm captures. One pass, a container stack of two.
inline void extractJsonKeys( std::string_view bytes, DataKeySink& sink )
{
    std::vector<char> stack;
    std::uint32_t     lineNo = 1;
    for( std::size_t i = 0; i < bytes.size(); ++i )
    {
        const char c = bytes[ i ];
        if( c == '\n' )
        {
            ++lineNo;
        }
        else if( c == '{' || c == '[' )
        {
            stack.push_back( c );
        }
        else if( ( c == '}' || c == ']' ) && !stack.empty() )
        {
            stack.pop_back();
        }
        else if( c == '"' )
        {
            const std::size_t open = i;
            std::size_t       j    = i + 1;
            while( j < bytes.size() && bytes[ j ] != '"' && bytes[ j ] != '\n' )
            {
                j += ( bytes[ j ] == '\\' ) ? 2 : 1;
            }
            const std::size_t close = std::min( j, bytes.size() );
            i                       = close;
            const std::size_t colon = bytes.find_first_not_of( " \t\r\n", close + 1 );
            const bool        isKey = colon != std::string_view::npos && bytes[ colon ] == ':';
            const bool level1       = stack.size() == 1 && stack[ 0 ] == '{';
            const bool level2       = stack.size() == 2 && stack[ 0 ] == '{' && stack[ 1 ] == '{';
            if( isKey && ( level1 || level2 ) )
            {
                sink.key( bytes.substr( open + 1, close - open - 1 ), lineNo, std::uint32_t( open ), std::uint32_t( std::min( close + 1, bytes.size() ) ) );
            }
        }
    }
}

// YAML: a `key:` line at column 0 (top level), or at the first deeper indent under a top-level key (second level) —
// the shapes queries/yaml/tags.scm captures for block mappings. Sequence items (`- key:`), comments and document
// markers are not keys; a block scalar's text is skipped while it is indented past the key that opened it.
inline void extractYamlKeys( std::string_view bytes, DataKeySink& sink )
{
    std::uint32_t lineNo       = 0;
    std::size_t   secondIndent = 0;   // 0 = not yet seen under the current top-level key
    for( std::size_t lineStart = 0; lineStart < bytes.size(); )
    {
        std::size_t lineEnd = bytes.find( '\n', lineStart );
        lineEnd             = lineEnd == std::string_view::npos ? bytes.size() : lineEnd;
        const std::string_view line = bytes.substr( lineStart, lineEnd - lineStart );
        ++lineNo;
        const std::size_t indent = line.find_first_not_of( ' ' );
        if( indent != std::string_view::npos && line[ indent ] != '#' && line[ indent ] != '-' && line[ indent ] != '\t'
            && !line.substr( indent ).starts_with( "..." ) )
        {
            std::size_t colon = line.find( ':', indent );
            while( colon != std::string_view::npos && colon + 1 < line.size() && line[ colon + 1 ] != ' ' && line[ colon + 1 ] != '\r' )
            {
                colon = line.find( ':', colon + 1 );
            }
            if( colon != std::string_view::npos )
            {
                std::string_view key = line.substr( indent, colon - indent );
                while( !key.empty() && key.back() == ' ' )
                {
                    key.remove_suffix( 1 );
                }
                if( key.size() >= 2 && ( key.front() == '"' || key.front() == '\'' ) && key.back() == key.front() )
                {
                    key = key.substr( 1, key.size() - 2 );
                }
                const bool top = indent == 0;
                if( !top && secondIndent == 0 )
                {
                    secondIndent = indent;
                }
                if( top || indent == secondIndent )
                {
                    sink.key( key, lineNo, std::uint32_t( lineStart + indent ), std::uint32_t( lineEnd ) );
                }
                if( top )
                {
                    secondIndent = 0;
                }
            }
        }
        lineStart = lineEnd + 1;
    }
}

// The data reader for a .json/.yml/.yaml: bounded keys; returns how many were found past the cap.
inline std::uint32_t extractLexicalDataKeys( std::uint32_t fileId, Lang lang, std::string_view bytes, std::vector<RawDef>& defs )
{
    DataKeySink sink{ fileId, lang, defs, dataFileKeyCap() };
    switch( lang )
    {
        case Lang::Json: extractJsonKeys( bytes, sink ); break;
        default:         extractYamlKeys( bytes, sink ); break;
    }
    return sink.cut;
}

// The full-index ceiling of a data language (0: none — code is never cut by its kind, only by --max-file-size). A switch,
// not `==` chains: test/langidentitycheck.sh ratchets the shared-file Lang equality predicates.
inline std::size_t dataFullIndexCeiling( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Json: return kMaxJsonConfigBytes;
        case Lang::Yaml: return kMaxYamlConfigBytes;
        default:         return 0;
    }
}

// The warning's spelling of a data language ("" for any other).
inline std::string_view dataLangWord( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Json: return "json";
        case Lang::Yaml: return "yaml";
        default:         return "";
    }
}

inline bool isDataKeysLang( Lang lang ) noexcept
{
    return dataFullIndexCeiling( lang ) != 0;
}

// The mode a file of this size and language is indexed in BEFORE any parse runs: Parsed (then the budget decides), the
// bounded-keys read of a data file past its ceiling, or the lexical read of any other file past --max-file-size.
inline FileIndexMode preParseIndexMode( Lang lang, std::size_t bytes, std::size_t maxFileBytes, bool ownReader = false ) noexcept
{
    if( ownReader )
    {
        return FileIndexMode::Parsed;   // a reader that bounds itself (reST's flat reader) keeps the file
    }
    if( isDataKeysLang( lang ) )
    {
        return bytes > dataFullIndexCeiling( lang ) ? FileIndexMode::DataKeysBounded : FileIndexMode::Parsed;
    }
    return bytes > maxFileBytes ? FileIndexMode::LexicalOverSize : FileIndexMode::Parsed;
}

// Index one file lexically in `mode` and record the mode on its health slot. A doc language (markdown, …) has no
// lexical reader: its file stays in the corpus (the --grep corpus, the file list) with no symbols, still disclosed.
inline void indexFileLexically( std::uint32_t fileId, const LangEntry& le, std::string_view bytes, FileIndexMode mode,
                                std::vector<RawDef>& defs, std::vector<RawRef>& refs, FileHealth& health )
{
    health           = FileHealth{};
    health.fileBytes = std::uint32_t( std::min<std::size_t>( bytes.size(), UINT32_MAX ) );
    health.indexMode = std::uint32_t( mode );
    // The whitespace sample the minified-suspect row reads (measureFileHealth's, minus the tree-only error walk): left
    // at 0 it would row every lexically read file as minified.
    const std::size_t wsSample = std::min( bytes.size(), kHealthWsSampleBytes );
    health.wsBytes             = std::uint32_t( std::count_if( bytes.begin(), bytes.begin() + std::ptrdiff_t( wsSample ), []( char c )
                                                               { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; } ) );
    if( isDataKeysLang( le.lang ) )
    {
        health.keysCut = extractLexicalDataKeys( fileId, le.lang, bytes, defs );
    }
    else if( !isDocLang( le.lang ) )
    {
        extractLexicalCode( fileId, le.lang, bytes, defs, refs );
    }
}

// ── the stderr warning (owner 2026-11-14: "print a warning to the user whenever the limit is found") ───────────────
// One line per file that met a limit, naming the file, its size, the limit, what happened and what raises it; at most
// kLimitWarningLines lines per PROCESS (an MCP session, or the HEAD snapshot a quality-delta ingests beside the tree,
// never repeats a path or floods), then one "and N more" line per ingest. stderr only: the answer bytes carry the
// disclosure as attributes (lexical_files=, keys_cut=, --skipped rows), and those are what an agent reads.
inline constexpr std::uint32_t kLimitWarningLines = 5;

struct LimitWarnings
{
    std::mutex             mutex;
    HashMap<std::string, char> warned;   // paths already named (value unused)
    std::uint32_t          printed = 0;
};

inline LimitWarnings& limitWarnings()
{
    static LimitWarnings state;
    return state;
}

inline double mebibytes( std::uint64_t bytes ) noexcept
{
    return double( bytes ) / ( 1024.0 * 1024.0 );
}

// "82.0 MiB", or "8.0 KiB" under one MiB (a --max-file-size=8K ceiling must not print as 0.0 MiB)
inline std::string sizeSpelling( std::uint64_t bytes )
{
    return bytes >= 1024u * 1024u ? std::format( "{:.1f} MiB", mebibytes( bytes ) ) : std::format( "{:.1f} KiB", double( bytes ) / 1024.0 );
}

inline std::string limitWarningLine( const std::string& path, const FileHealth& health, std::size_t maxFileBytes, const LangEntry* le )
{
    const std::string size = sizeSpelling( health.fileBytes );
    switch( FileIndexMode( health.indexMode ) )
    {
        case FileIndexMode::LexicalOverSize:
            return std::format( "ripwire: warning: {} ({}) exceeds --max-file-size {}; indexed lexically (raise with --max-file-size=N)\n",
                                path, size, sizeSpelling( maxFileBytes ) );
        case FileIndexMode::LexicalOverBudget:
            return std::format( "ripwire: warning: {} ({}) ran past its parse budget of {:.1f} s; indexed lexically (raise with RIPWIRE_PARSE_BUDGET=<scale>)\n",
                                path, size, parseBudgetSecondsFor( health.fileBytes ) );
        case FileIndexMode::DataKeysBounded:
        {
            // The key cap is the limit that loses data; a data file past its full-index ceiling whose top-level keys all fit
            // is fully listed at that depth, so it warns nothing (lexical_files= and its keys-bounded row still disclose it).
            // A repo's own big fixtures (this one has 15) would otherwise put a warning on every run of every verb.
            if( health.keysCut == 0 )
            {
                return {};
            }
            const Lang        lang    = le != nullptr ? le->lang : Lang::Json;
            const std::size_t ceiling = dataFullIndexCeiling( lang );
            return std::format( "ripwire: warning: {} ({}) exceeds the {} full-index ceiling {} KiB; top-level keys indexed lexically, {} cut at {} (raise with RIPWIRE_DATA_KEYS=N)\n",
                                path, size, dataLangWord( lang ), ceiling / 1024, health.keysCut, dataFileKeyCap() );
        }
        case FileIndexMode::LexicalNestRefused:
        case FileIndexMode::Parsed:
            break;
    }
    return {};
}

// Called once per ingest, serially, after the parse pool: fileId order, then the hard-limit drops, so the lines are
// deterministic for one tree.
inline void warnIndexLimits( const IngestResult& result, std::size_t maxFileBytes )
{
    std::vector<std::string> lines;
    for( std::size_t fileId = 0; fileId < result.files.size() && fileId < result.fileHealth.size(); ++fileId )
    {
        if( isLexicallyIndexed( result.fileHealth[ fileId ] ) )
        {
            const std::string& path = result.files[ fileId ];
            std::string        line = limitWarningLine( path, result.fileHealth[ fileId ], maxFileBytes, lookupLang( lowerExtensionOf( path ) ) );
            if( !line.empty() )
            {
                lines.push_back( std::move( line ) );
            }
        }
    }
    for( const SkippedOversize& sk : result.skippedOversize )
    {
        lines.push_back( std::format( "ripwire: warning: {} ({}) exceeds the {} hard limit; not indexed (no option raises it)\n",
                                      sk.path, sizeSpelling( sk.sizeBytes ), sizeSpelling( sk.limitBytes ) ) );
    }
    if( lines.empty() )
    {
        return;
    }
    LimitWarnings&              state = limitWarnings();
    const std::lock_guard<std::mutex> lock( state.mutex );
    std::uint64_t               more = 0;
    for( std::string& line : lines )
    {
        if( !state.warned.try_emplace( line, 0 ).second )
        {
            continue;   // this exact event was already named in this process
        }
        if( state.printed < kLimitWarningLines )
        {
            ++state.printed;
            rw::emitRaw( stderr, line.c_str() );
        }
        else
        {
            ++more;
        }
    }
    if( more > 0 )
    {
        rw::emitTo( stderr, "ripwire: warning: and {} more file(s) met an index limit (the skipped verb lists each)\n", more );
    }
}

} // namespace
} // namespace rw
