#pragma once
// editcheckdecl.h — the C/C++ DECLARATION/DEFINITION IDENTITY behind --edit-check (editcheck.h).
//
// The field report: `int scale( int x, int factor = 2 );` in lib.h, its definition in lib.cpp, three callers passing 1,
// 1 and 2 arguments, and a trailing `int bias = 0` added to both. Every call still compiles. The verb (1) refused the
// bare name as "2 distinct contracts" — the prototype and its definition sit in two files, and a contract was keyed per
// (file, scope) — (2) answered the definition's handle with incompatible="3", because the arity test read the
// DEFINITION's parameter list, which carries no defaults (C++ puts them on the declaration a caller sees), and (3)
// refused the header handle the refusal itself had suggested.
//
// THE IDENTITY RULE. A bodyless C-family declaration D stands for a bodied definition F when ALL of these hold:
//   * same name, and the SAME FULL SCOPE CHAIN — every enclosing namespace and class, outermost first, plus the
//     declarator's own written qualifier (`int outer::detail::f(…)`, `int S::f(…)`; a leading `::` is absolute).
//     Symbol::scope holds only the INNERMOST label, so `outer::detail::f` and `::detail::f` shared it and one lent its
//     default to the other (review M1). The chain is read off the source by editCheckScopeChain; a file whose braces do
//     not balance (a macro that opens a namespace, a brace inside an #if/#else pair) or a template-qualified declarator
//     yields an UNKNOWN chain, and an unknown chain never pairs;
//   * the same cv/ref qualifiers on the member (`int f(…) const` is another function than `int f(…)`);
//   * F's file is D's file, or F's file #includes D's file directly — includeProofOfDeclFiles, the SAME positive proof the
//     file:name selector widening keeps a candidate by;
//   * F has external linkage, unless D sits in F's own file (keepProvenCandidates' clause 3);
//   * the PARAMETER-TYPE LISTS are equal — the declared types, names, default values and comments stripped. This is what
//     keeps real overloads apart: `scale( int, int = 2 )` never lends its default to `scale( double, int )`.
// The types are read off the SOURCE TEXT of each signature span (no parameter-type fact is indexed). A list the reader
// cannot parse into exactly `params` entries — a function-pointer parameter, a macro-built list, a stale span, one past
// kEditCheckSigCap — matches nothing.
//
// A false "compatible" is worse than a false "incompatible" (the flag is the verb's one call-site signal), so every rule
// fails CLOSED: anything unproven keeps the stricter reading, and editCheckTieDeclaration says WHICH way it failed —
// Different (provably another function) or Unproven (it may declare F; the proof could not be made), so the answer can
// disclose the unproven ones that carry defaults (defaults_untied=) instead of flagging their callers silently.

#include "model.h"
#include "graph.h"              // includeProofOfDeclFiles / langCompatible / isDefinitionNotDeclaration
#include "infra/namesplit.h"    // namesplit::isIdentChar — the ONE ASCII identifier-byte test
#include "cppscopechain.h"      // editCheckBlankComments / editCheckParamOpen / EditCheckBraceLexer / editCheckWrittenQualifier
#include "infra/ownedfile.h"    // the source read

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The pre-apply preview's one in-memory file: the merged tree's spans for that file index the spliced bytes, not the disk.
struct EditCheckSpliced
{
    std::string_view bytes;
    std::uint32_t    fileId;
    bool             engaged;
};

// A signature longer than this is not parsed (it does not pair, and an unproven declaration is disclosed as such).
constexpr std::uint32_t kEditCheckSigCap = 16384;   // disclosed as defaults_untied= beside a nonzero incompatible=

// One file's comment-blanked text. `whole` is false when the file could not be opened or its read stopped on an error:
// the text is then empty or partial, so a signature read from it proves nothing (editCheckSignatureOf discloses it).
struct EditCheckFileText
{
    std::uint32_t fileId;
    std::string   body;
    bool          whole;
};

// The comment-blanked text of the files one answer reads, each read once. The preview's spliced file is read from memory.
class EditCheckSources
{
public:
    EditCheckSources( const IngestResult& input, const EditCheckSpliced& splicedFile ) : ing( input ), spliced( splicedFile ) {}

    const EditCheckFileText& text( std::uint32_t fileId )
    {
        for( const EditCheckFileText& f : files )
        {
            if( f.fileId == fileId )
            {
                return f;
            }
        }
        files.push_back( read( fileId ) );
        editCheckBlankComments( files.back().body );
        return files.back();
    }

private:
    EditCheckFileText read( std::uint32_t fileId ) const
    {
        if( spliced.engaged && spliced.fileId == fileId )
        {
            return { fileId, std::string( spliced.bytes ), true };
        }
        std::string body;
        OwnedFile   in = openOwnedFile( diskPath( ing, fileId ).c_str(), "rb" );
        char        buf[ 4096 ];
        for( std::size_t n = 0; in && ( n = std::fread( buf, 1, sizeof( buf ), in.file ) ) > 0; )
        {
            body.append( buf, n );
        }
        const bool whole = in && std::ferror( in.file ) == 0;
        return { fileId, std::move( body ), whole };
    }

    const IngestResult&           ing;
    EditCheckSpliced              spliced;
    std::deque<EditCheckFileText> files;   // a deque: a reference text() handed out stays valid while later files are appended
};

// ── one parameter's type ──────────────────────────────────────────────────────────────────────────────────────
// Tokens: identifiers (with `::` kept inside them) and single punctuation bytes, so whitespace never decides equality. An
// attribute (`[[maybe_unused]]`) is not part of the type and is skipped.
inline std::vector<std::string> editCheckTokens( std::string_view param )
{
    const auto identAt = [ & ]( std::size_t i )
    {
        return namesplit::isIdentChar( param[i] ) || ( param[i] == ':' && i + 1 < param.size() && param[ i + 1 ] == ':' );
    };
    std::vector<std::string> toks;
    std::size_t              i = 0;
    while( i < param.size() )
    {
        if( param.substr( i, 2 ) == "[[" )
        {
            const std::size_t close = param.find( "]]", i + 2 );
            i = ( close == std::string_view::npos ) ? param.size() : close + 2;
            continue;
        }
        if( !identAt( i ) )
        {
            if( param[i] != ' ' && param[i] != '\t' && param[i] != '\n' && param[i] != '\r' )
            {
                toks.emplace_back( 1, param[i] );
            }
            ++i;
            continue;
        }
        std::string tok;
        while( i < param.size() && identAt( i ) )
        {
            const std::size_t step = ( param[i] == ':' ) ? 2u : 1u;
            tok.append( param.substr( i, step ) );
            i += step;
        }
        toks.push_back( std::move( tok ) );
    }
    return toks;
}

// One parameter's TYPE: its tokens minus the declarator name, which is dropped when it is the last identifier (before an
// array suffix, if any) and a type token precedes it — `int x` -> `int`, `const Foo& f` -> `const Foo &`, `int a[3]` ->
// `int [ 3 ]`. A keyword type is never mistaken for a name (`unsigned long` keeps both), and a lone qualifier is not a
// type (`const Foo` keeps `Foo`).
inline std::vector<std::string> editCheckTypeTokens( std::string_view param )
{
    static constexpr std::string_view kTypeWords[] = { "int", "long", "short", "char", "unsigned", "signed", "double", "float", "bool",
                                                       "void", "auto", "wchar_t", "char8_t", "char16_t", "char32_t" };
    static constexpr std::string_view kQualWords[] = { "const", "volatile", "struct", "class", "enum", "union", "typename", "register",
                                                       "restrict", "__restrict" };
    const auto in = []( const std::string& t, std::span<const std::string_view> set ) { return std::find( set.begin(), set.end(), t ) != set.end(); };

    std::vector<std::string> toks   = editCheckTokens( param );
    const auto               suffix = std::find( toks.begin(), toks.end(), std::string( "[" ) );
    const std::size_t        nameAt = ( !toks.empty() && toks.back() == "]" ) ? std::size_t( suffix - toks.begin() ) : toks.size();
    if( nameAt < 2 )
    {
        return toks;
    }
    const std::string& name       = toks[ nameAt - 1 ];
    const bool         typeBefore = std::any_of( toks.begin(), toks.begin() + std::ptrdiff_t( nameAt - 1 ),
                                                 [ & ]( const std::string& t ) { return !in( t, kQualWords ); } );
    if( namesplit::isIdentChar( name[0] ) && !in( name, kTypeWords ) && !in( name, kQualWords ) && typeBefore )
    {
        toks.erase( toks.begin() + std::ptrdiff_t( nameAt - 1 ) );
    }
    return toks;
}

// The raw parameters between the '(' at `open` and its matching ')' (at `closeAt`), each with whether it carries a
// default. Split at depth-0 commas; '<'/'>' nest only in a TYPE, never after its '=' (a default value may compare).
struct EditCheckRawParams
{
    std::vector<std::string_view> text;
    std::vector<char>             defaulted;
    std::size_t                   closeAt;
    bool                          closed;
};

inline EditCheckRawParams editCheckSplitParams( std::string_view text, std::size_t open )
{
    EditCheckRawParams raw{};
    int                depth = 0, angle = 0;
    bool               inDefault = false;
    std::size_t        start     = open + 1;
    for( std::size_t i = open + 1; i < text.size() && !raw.closed; ++i )
    {
        const char c        = text[i];
        const bool atTop    = depth == 0 && ( angle == 0 || inDefault );
        const bool assigns  = c == '=' && depth == 0 && angle == 0 && text.substr( i - 1, 3 ).find( "==" ) == std::string_view::npos
                           && std::string_view( "!<>" ).find( text[ i - 1 ] ) == std::string_view::npos;
        if( atTop && ( c == ')' || c == ',' ) )
        {
            raw.text.push_back( text.substr( start, i - start ) );
            raw.defaulted.push_back( char( inDefault ? 1 : 0 ) );
            start       = i + 1;
            inDefault   = false;
            angle       = 0;
            raw.closed  = ( c == ')' );
            raw.closeAt = i;
            continue;
        }
        depth     += ( c == '(' || c == '[' || c == '{' ) ? 1 : ( c == ')' || c == ']' || c == '}' ) ? -1 : 0;
        angle     += ( inDefault || depth != 0 ) ? 0 : ( c == '<' ) ? 1 : ( c == '>' && angle > 0 ) ? -1 : 0;
        inDefault  = inDefault || assigns;
    }
    return raw;
}

// The member's cv/ref qualifiers after its parameter list, up to the body, a ';', an '=' (`= 0`, `= default`), a
// ctor-initializer ':' or a trailing return type: `const`, `volatile`, `&`, `&&`, in order.
inline std::string editCheckMemberQualifiers( std::string_view text, std::size_t afterParams )
{
    std::string quals;
    for( std::size_t i = afterParams; i < text.size(); ++i )
    {
        const char c = text[i];
        if( c == '{' || c == ';' || c == '=' || ( c == ':' && text.substr( i, 2 ) != "::" ) || text.substr( i, 2 ) == "->" )
        {
            break;
        }
        if( c == '&' )
        {
            quals += '&';
        }
        else if( namesplit::isIdentChar( c ) && ( i == 0 || !namesplit::isIdentChar( text[ i - 1 ] ) ) )
        {
            const std::size_t end  = text.find_first_not_of( "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", i );
            const std::string_view w = text.substr( i, ( end == std::string_view::npos ? text.size() : end ) - i );
            quals += ( w == "const" || w == "volatile" ) ? std::string( w ) + " " : std::string();
        }
    }
    return quals;
}

// ── one signature's facts ─────────────────────────────────────────────────────────────────────────────────────
// Each parameter's type and how many carry a default; the full scope chain (nullopt = unknown) and the member qualifiers.
// `ok` is false when the text does not hold `name( … )`, the list does not close, it is variadic, it exceeds
// kEditCheckSigCap, or it does not split into exactly `params` entries — and a list that is not ok matches nothing.
// `mayDefault` is whether the parameter text holds an '=' at all: what an unparsed declaration is disclosed on.
struct EditCheckSignature
{
    std::vector<std::vector<std::string>>   types;
    std::optional<std::vector<std::string>> chain;
    std::string                             quals;
    std::uint16_t                           defaulted;
    bool                                    ok;
    bool                                    mayDefault;
    // The DISCLOSE sink: a signature that cannot be read is not a signature without defaults. mayDefault is what the
    // answer's defaults_untied= counts, so an unread declaration is disclosed beside the flags it might admit.
    enum class DisclosureWhy : std::uint8_t
    {
        UnreadableFile,   // the file could not be opened, or its read stopped on an error
    };
    void disclose( DisclosureWhy ) noexcept   // one reason: unproven, and it may carry a default
    {
        ok         = false;
        mayDefault = true;
    }
};

inline EditCheckSignature editCheckSignatureOf( EditCheckSources& sources, const Symbol& s )
{
    EditCheckSignature       sig{};
    const EditCheckFileText& source = sources.text( s.fileId );
    const std::string&       file   = source.body;
    if( !source.whole )
    {
        DISCLOSE( sig, EditCheckSignature::DisclosureWhy::UnreadableFile, "edit-check: a C/C++ source could not be read whole — its signature is unproven and counted by defaults_untied=" );
        return sig;
    }
    const std::uint32_t    end   = std::min<std::uint32_t>( isDefinitionNotDeclaration( s ) ? s.sigEndByte : s.endByte, std::uint32_t( file.size() ) );
    if( end <= s.sigStartByte || end - s.sigStartByte > kEditCheckSigCap )
    {
        sig.mayDefault = end > s.sigStartByte;   // past the cap: unread, so it may carry a default
        return sig;
    }
    const std::string_view text          = std::string_view( file ).substr( s.sigStartByte, end - s.sigStartByte );
    const auto [ nameAt, open ]          = editCheckParamOpen( text, s.name );
    const EditCheckRawParams raw         = ( open == std::string_view::npos ) ? EditCheckRawParams{} : editCheckSplitParams( text, open );
    sig.mayDefault                       = open != std::string_view::npos && text.find( '=', open ) != std::string_view::npos;
    if( !raw.closed )
    {
        return sig;
    }
    for( std::size_t k = 0; k < raw.text.size(); ++k )
    {
        const std::string_view param = raw.defaulted[k] ? raw.text[k].substr( 0, raw.text[k].find( '=' ) ) : raw.text[k];
        if( param.find( "..." ) != std::string_view::npos )
        {
            return sig;   // variadic: never a fixed list
        }
        if( param.find( '(' ) != std::string_view::npos )
        {
            return sig;   // a function-pointer, function-type or decltype parameter: its declarator name is not stripped,
                          // so the list is unparsed (Unproven, disclosed on mayDefault), never compared as types
        }
        sig.defaulted += raw.defaulted[k] ? 1u : 0u;
        sig.types.push_back( editCheckTypeTokens( param ) );
    }
    if( sig.types.size() == 1 && ( sig.types[0].empty() || sig.types[0] == std::vector<std::string>{ "void" } ) )
    {
        sig.types.clear();   // `()` and `(void)`: no parameter
    }
    sig.ok    = sig.types.size() == s.params;
    sig.quals = editCheckMemberQualifiers( file, s.sigStartByte + raw.closeAt + 1 );

    const std::size_t                              nameInFile = s.sigStartByte + nameAt;
    const std::optional<EditCheckWrittenQualifier> written    = editCheckWrittenQualifier( file, nameInFile );
    EditCheckBraceLexer                            lexer( file );
    std::optional<std::vector<std::string>>        chain      = lexer.chainAt( nameInFile );   // also proves the file's braces readable
    // a qualified, non-absolute declarator after `using namespace X;` may name X's member: its chain is not certain
    const bool usingAmbiguous = written && !written->absolute && !written->names.empty() && lexer.usingDirectiveBefore();
    chain = ( written && written->absolute && chain ) ? std::optional<std::vector<std::string>>( std::vector<std::string>{} ) : chain;
    if( written && chain && !usingAmbiguous )
    {
        chain->insert( chain->end(), written->names.begin(), written->names.end() );
        sig.chain = std::move( chain );
    }
    return sig;
}

// ── the tie ───────────────────────────────────────────────────────────────────────────────────────────────────
enum class EditCheckTie : std::uint8_t
{
    Declares,    // D declares F: the identity rule held
    Different,   // provably another function (another name, chain, qualifier, parameter-type list, or linkage)
    Unproven,    // may declare F, and could not be proven to: an unknown chain, an unparsed list, an unproven #include
};

struct EditCheckTieResult
{
    EditCheckTie  tie;
    std::uint16_t defaulted;    // the declaration's default count, on Declares
    bool          mayDefault;   // on Unproven: the declaration may carry a default (what defaults_untied= counts)
};

// The identity rule's parser-field half, read off the two symbols alone (no source read): a pair failing it is Different.
// Callers that test many pairs (editcheck.h editCheckDeclFoldTargets) ask it FIRST, so a definition's signature is read
// only for a declaration that could declare it (checklist 30(c): the source reads stay bounded by the candidate pairs).
inline bool editCheckTieCandidate( const Symbol& d, const Symbol& f ) noexcept
{
    return d.name == f.name && d.scope == f.scope && langCompatible( d.lang, Lang::C ) && langCompatible( f.lang, Lang::C )
        && !isDefinitionNotDeclaration( d ) && isDefinitionNotDeclaration( f ) && d.params == f.params
        && ( f.internalLinkage == 0 || d.fileId == f.fileId );
}

// THE IDENTITY RULE, for one (declaration, definition) pair. `defSig` is the definition's own signature, read once.
inline EditCheckTieResult editCheckTieDeclaration( const IngestResult& ing, EditCheckSources& sources, NodeId decl, NodeId def,
                                                   const EditCheckSignature& defSig )
{
    const Symbol& d = ing.symbols[ decl ];
    const Symbol& f = ing.symbols[ def ];
    if( !editCheckTieCandidate( d, f ) )
    {
        return { EditCheckTie::Different, 0, false };
    }
    const EditCheckSignature declSig = editCheckSignatureOf( sources, d );
    if( defSig.ok && declSig.ok
        && ( declSig.types != defSig.types || declSig.quals != defSig.quals || ( declSig.chain && defSig.chain && *declSig.chain != *defSig.chain ) ) )
    {
        return { EditCheckTie::Different, 0, false };
    }
    const bool proven = defSig.ok && declSig.ok && declSig.chain && defSig.chain
                     && ( d.fileId == f.fileId || includeProofOfDeclFiles( ing, { decl }, { def } )[ f.fileId ] != 0 );
    if( !proven )
    {
        return { EditCheckTie::Unproven, 0, declSig.ok ? declSig.defaulted > 0 : declSig.mayDefault };
    }
    return { EditCheckTie::Declares, declSig.defaulted, false };
}

// Per member of the overload set, the FEWEST arguments a call may pass: `params` minus the defaults of the declaration
// that declares it and carries the most of them (C++ lets a redeclaration add defaults; the widest reading is the
// one-sided one). `fromDecl` is true when any member's range was widened that way — the root's defaults_from="decl".
// `untied` counts the Unproven declarations that may carry a default: the root's defaults_untied=.
struct EditCheckDeclDefaults
{
    std::vector<std::uint16_t> minArity;   // parallel to the overload set
    std::uint32_t              untied;
    bool                       fromDecl;
};

// One definition's minimum; its untied declarations are appended to `untied` (an overload set may meet one declaration
// from several members, so the caller counts distinct ids). Only a fixed-arity C-family DEFINITION can be widened —
// anything else is already a wildcard (arityExact 0) or has no declaration to read.
inline std::uint16_t editCheckMinArity( const IngestResult& ing, EditCheckSources& sources, NodeId def, std::vector<NodeId>& untied )
{
    const Symbol& f = ing.symbols[ def ];
    if( !langCompatible( f.lang, Lang::C ) || f.arityExact == 0 || !isDefinitionNotDeclaration( f ) )
    {
        return f.params;
    }
    const EditCheckSignature defSig   = editCheckSignatureOf( sources, f );
    std::uint16_t            minArity = f.params;
    for( NodeId cand = 0; cand < ing.symbols.size(); ++cand )
    {
        if( ing.symbols[ cand ].name != f.name || cand == def )
        {
            continue;
        }
        const EditCheckTieResult tie = editCheckTieDeclaration( ing, sources, cand, def, defSig );
        if( tie.tie == EditCheckTie::Declares )
        {
            minArity = std::min<std::uint16_t>( minArity, std::uint16_t( f.params - std::min( tie.defaulted, f.params ) ) );
        }
        if( tie.tie == EditCheckTie::Unproven && tie.mayDefault )
        {
            untied.push_back( cand );
        }
    }
    return minArity;
}

inline EditCheckDeclDefaults editCheckDeclDefaults( const IngestResult& ing, std::span<const NodeId> overloadNodes, const EditCheckSpliced& spliced )
{
    EditCheckDeclDefaults res{};
    EditCheckSources      sources( ing, spliced );
    res.minArity.reserve( overloadNodes.size() );
    std::vector<NodeId> untiedDecls;   // one declaration two overloads both meet is ONE untied declaration
    for( NodeId ov : overloadNodes )
    {
        const std::uint16_t minArity = editCheckMinArity( ing, sources, ov, untiedDecls );
        res.minArity.push_back( minArity );
        res.fromDecl = res.fromDecl || minArity < ing.symbols[ ov ].params;
    }
    std::sort( untiedDecls.begin(), untiedDecls.end() );
    res.untied = std::uint32_t( std::unique( untiedDecls.begin(), untiedDecls.end() ) - untiedDecls.begin() );
    ENSURES( res.minArity.size() == overloadNodes.size() );
    return res;
}

}   // namespace rw
