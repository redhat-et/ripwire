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
#include "cppscopechain.h"      // editCheckBlankComments / editCheckParamOpen / EditCheckBraceLexer / editCheckWrittenQualifier / the parameter-list readers
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

// THE STALE PAIR (EDIT-CHECK-ARITY): a bodyless declaration D that WOULD declare definition F but for the parameter list
// — the edit changed F's list and D still spells the old one (`int jq_start( jq_state*, jv, int )` in jq.h beside a
// four-parameter definition in execute.c). For "did my edit break a contract" the two are ONE symbol: the bare name answers
// at F instead of refusing "2 distinct contracts", and the answer names D and its old count (editcheck.h decl_pair=), which
// is itself the finding — every caller that sees only the header still compiles against the old list. Every other clause
// of the identity rule holds: same name and innermost scope, both C-family, F external or in D's file, F's file is D's or
// #includes it directly; and for a C++ definition the full scope chain and member qualifiers are both read and equal
// (a C definition has no namespace, and a C file's macros can make the chain unreadable for no reason that matters here).
inline bool editCheckStalePair( const IngestResult& ing, EditCheckSources& sources, NodeId decl, NodeId def )
{
    const Symbol& d = ing.symbols[ decl ];
    const Symbol& f = ing.symbols[ def ];
    if(    d.name != f.name || d.scope != f.scope || d.params == f.params || !langCompatible( d.lang, Lang::C ) || !langCompatible( f.lang, Lang::C )
        || isDefinitionNotDeclaration( d ) || !isDefinitionNotDeclaration( f ) || ( f.internalLinkage != 0 && d.fileId != f.fileId ) )
    {
        return false;
    }
    if( f.lang != Lang::C )
    {
        const EditCheckSignature declSig = editCheckSignatureOf( sources, d );
        const EditCheckSignature defSig  = editCheckSignatureOf( sources, f );
        if( !declSig.chain || !defSig.chain || *declSig.chain != *defSig.chain || declSig.quals != defSig.quals )
        {
            return false;
        }
    }
    return d.fileId == f.fileId || includeProofOfDeclFiles( ing, { decl }, { def } )[ f.fileId ] != 0;
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
// from several members, so the caller counts distinct ids). Only a C-family DEFINITION can be widened: a fixed-arity one,
// or a C++ one whose own list already carries a default or a pack (arityExact 0), whose range editcheckarity.h reads off
// its text and lowers by what is returned here. Anything else has no declaration to read.
inline std::uint16_t editCheckMinArity( const IngestResult& ing, EditCheckSources& sources, NodeId def, std::vector<NodeId>& untied )
{
    const Symbol& f = ing.symbols[ def ];
    if( !langCompatible( f.lang, Lang::C ) || ( f.arityExact == 0 && langFacts( f.lang ).arityReader != ArityReader::Cpp ) || !isDefinitionNotDeclaration( f ) )
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
