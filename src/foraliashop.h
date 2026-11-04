#pragma once
// foraliashop.h — XF-ALIAS-HOP, the for verb's surface: an <aliases> block after the answer when the name the task spells has an
// alias definition (the printed rows first, then the rest: an alias-only name in a sentence prints as literal lines, not rows). The walk itself is aliashop.h aliasChain (the one alias hop); this file only picks the rows and prints.
//
// WHY. `--for=ColumnPtr` printed `using ColumnPtr = COW<IColumn>::Ptr` and stopped: what the alias stands for (COW::Ptr, then
// `using Ptr = immutable_ptr<Derived>` in COW.h, then the class immutable_ptr) and the class it points at (IColumn, its members)
// took two more calls (--defs to_next, then --defs again). WHAT. One <chain> per distinct alias walk (at most kAliasHopChains,
// total= counts all), one <h> row per definition reached, its declaration as text (cut past kAliasHopSigBytes, cut="1"), a
// type's member count and first kAliasHopMemberNames names, and a <leaf> per target spelling no definition binds. Present-only:
// a task whose name has no alias definition gets "" (alias-free answers byte-identical). Outside est_tokens, its
// own allowance (no auto-served body pays for it); a token budget prints a held marker. XML only. RIPWIRE_NO_ALIAS_HOP (any
// value) turns it off.

#include "aliashop.h"
#include "forreexport.h"   // shortkey_detail::routeName / sentenceName — the names the task spells
#include "lexical.h"       // routeLower, lexicalScanText
#include "model.h"
#include "nextverb.h"      // nextFlag / nextAttrXml
#include "serialize.h"     // escapeXml, symTag, truncateUtf8WithEllipsis

#include <algorithm>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kAliasHopChains      = 3;     // chains printed (total= counts all distinct walks)
inline constexpr std::size_t kAliasHopSigBytes    = 240;   // a declaration's text is cut here (cut="1"); a runaway guard
inline constexpr std::size_t kAliasHopMemberNames = 12;    // member names listed on a type row (members= counts all)
static_assert( kAliasHopChains == 3 && kAliasHopSigBytes == 240 && kAliasHopMemberNames == 12, "kAliasHopLegend states these caps: move the sentence with the constants" );

inline constexpr std::string_view kAliasHopLegend =
    "<!-- aliases: the name the task spells (the route's name, else the sentence's one code-shaped name) has an alias definition "
    "(another name for its written target); each chain follows one to what it names, the printed rows first. chain of= the alias, p= l= its file and line, to= its written target, also=N N more same-named alias rows walk "
    "the same chain; h n= t= sc= p= l=: a definition the chain reaches (its name, kind, scope, file, line), via=\"alias\" (reached through the alias, never a call edge), d= hops from the "
    "alias (at most 4; depth_capped=\"1\" on the chain: an alias was still to follow), arg=\"1\" a type named as a template argument "
    "of the first target (the pointee), cands=N the spelling bound N definitions (3 kept); the text is the declaration (cut=\"1\" past "
    "240 bytes; unread=\"1\": its file could not be read, so no text); members=N the type's member functions, m= the first 12 names; leaf n=: a target spelling that binds no definition in "
    "the tree (std, a template parameter, outside code), never followed; cycle=\"1\": a definition met twice ends the walk. total= the "
    "distinct chains, shown= printed (3 at most), capped=\"1\" if cut. next= the call that lists the users. The block is not in "
    "est_tokens -->";

namespace aliashop_for_detail
{

// The declaration text of `s` (an alias row: the whole declaration; any other: its signature), whitespace folded, cut past the cap.
inline std::string declText( const IngestResult& ing, const Symbol& s, std::string& scratch, std::uint32_t& textOf, const std::string*& text, bool& cut, bool& unread )
{
    if( textOf != s.fileId )
    {
        text   = lexicalScanText( ing, s.fileId, scratch );
        textOf = s.fileId;
    }
    const std::uint32_t end = aliasTargetRow( ing, s ) ? s.endByte : s.sigEndByte;
    std::string out;
    if( text == nullptr || end > text->size() || end <= s.sigStartByte )
    {
        unread = text == nullptr || end > text->size();   // could not read: said on the row (unread="1"), never an empty declaration
        return out;
    }
    out = foldAliasTarget( std::string_view( *text ).substr( s.sigStartByte, end - s.sigStartByte ) );   // the one fold (defslookup.h)
    while( !out.empty() && ( out.back() == '{' || out.back() == ';' || out.back() == ' ' ) )
    {
        out.pop_back();
    }
    cut = out.size() > kAliasHopSigBytes;
    truncateUtf8WithEllipsis( out, kAliasHopSigBytes );
    return out;
}

}   // namespace aliashop_for_detail

inline bool forAliasHopOn()
{
    return std::getenv( "RIPWIRE_NO_ALIAS_HOP" ) == nullptr;
}

struct ForAliasHopArgs
{
    std::string_view           task;
    std::string_view           routeNote;
    const std::vector<NodeId>* printed = nullptr;   // the answer's printed definition rows, in answer order
    bool                       held    = false;     // a token budget is set
};

// The <aliases> block ("" when the name the task spells has no alias definition with a written target).
inline std::string renderForAliasHops( const IngestResult& ing, const ForAliasHopArgs& a )
{
    if( a.printed == nullptr || !forAliasHopOn() || ing.aliasTargets.empty() )
    {
        return {};
    }
    // the names the task spells: the route's name-exact subject, else the sentence's one code-shaped name
    std::string_view subject = shortkey_detail::routeName( a.routeNote );
    if( subject.empty() )
    {
        subject = shortkey_detail::sentenceName( a.task );
    }
    if( subject.empty() )
    {
        return {};
    }
    const std::size_t      cut  = std::min( subject.rfind( "::" ), subject.rfind( '.' ) );
    const std::string_view leaf = cut == std::string_view::npos ? subject : subject.substr( subject[ cut ] == '.' ? cut + 1 : cut + 2 );
    const std::string      want = routeLower( leaf );
    // the alias rows the answer printed first (answer order), then the other alias definitions of the name (id order): a sentence
    // that names an alias-only name prints them as literal lines, not rows (forreexport.h sentenceNameUnresolved)
    std::vector<NodeId> rows;
    for( const NodeId n : aliasRowsAmong( ing, *a.printed ) )
    {
        if( routeLower( ing.symbols[ n ].name ) == want )
        {
            rows.push_back( n );
        }
    }
    for( const NodeId n : aliasRowsAmong( ing, resolveAllByName( ing, leaf ) ) )
    {
        if( ing.symbols[ n ].name == leaf && std::ranges::find( rows, n ) == rows.end() )
        {
            rows.push_back( n );
        }
    }
    if( rows.empty() )
    {
        return {};
    }
    // one walk per row (rows are few: the printed namesakes); equal walks merge (also=)
    struct Walked
    {
        AliasHopChain chain;
        std::size_t   also = 0;
    };
    std::vector<Walked> walks;
    aliashop_detail::BindCache cache;   // one per answer: the namespace verdicts the walks share
    for( const NodeId n : rows )
    {
        AliasHopChain c = aliasChain( ing, n, cache );
        if( c.steps.empty() && c.leaves.empty() )
        {
            continue;
        }
        const auto same = std::ranges::find_if( walks, [ & ]( const Walked& w )
                                                {
                                                    return w.chain.leaves == c.leaves && std::ranges::equal( w.chain.steps, c.steps, []( const AliasHopStep& x, const AliasHopStep& y ) { return x.def == y.def && x.arg == y.arg; } );
                                                } );
        if( same != walks.end() )
        {
            ++same->also;
            continue;
        }
        walks.push_back( { std::move( c ), 0 } );
    }
    if( walks.empty() )
    {
        return {};
    }
    // a walk that reaches a definition before one that reaches only leaves (the answer is where a definition is), else answer order
    std::ranges::stable_sort( walks, []( const Walked& x, const Walked& y ) { return !x.chain.steps.empty() && y.chain.steps.empty(); } );
    std::string       out;
    std::vector<char> esc;
    const auto attr = [ & ]( std::string_view k, std::string_view v ) { out.append( " " ).append( k ).append( "=\"" ).append( escapeXml( v, esc ) ).append( "\"" ); };
    const auto num  = [ & ]( std::string_view k, std::size_t v ) { out.append( " " ).append( k ).append( "=\"" ).append( std::to_string( v ) ).append( "\"" ); };
    const std::size_t shown = std::min( walks.size(), kAliasHopChains );
    if( a.held )
    {
        out = "<!-- aliases held=\"budget\": a token budget is set, so the alias chains are not printed (they sit outside est_tokens); total= "
              "the distinct chains; ask again without the token budget for the rows --><aliases held=\"budget\"";
        num( "total", walks.size() );
        return out.append( "/>" );
    }
    // the type rows' member functions: ONE scan over the symbols for every type the printed chains reach (hoisted out of the rows)
    std::vector<std::string> typeScopes;   // the type's name: the last scope segment its members carry
    std::vector<NodeId>      typeIds;
    for( std::size_t w = 0; w < shown; ++w )
    {
        for( const AliasHopStep& st : walks[ w ].chain.steps )
        {
            const Symbol& s = ing.symbols[ st.def ];
            if( ( s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface ) && std::ranges::find( typeIds, st.def ) == typeIds.end() )
            {
                typeIds.push_back( st.def );
                typeScopes.push_back( s.name );   // a C++ member's scope ends with its class's name (a class's own scope is its name)
            }
        }
    }
    std::vector<std::size_t>              memberCount( typeIds.size(), 0 );
    std::vector<std::vector<std::string>> memberNames( typeIds.size() );
    // a member in a source file that defines its own same-named type is that type's (an example .cpp's `class IColumn`), never the
    // header type's: the files that define a namesake of each type, read once
    std::vector<std::vector<std::uint32_t>> namesakeFiles( typeIds.size() );
    for( std::size_t k = 0; k < typeIds.size(); ++k )
    {
        for( const NodeId n : resolveAllByName( ing, ing.symbols[ typeIds[ k ] ].name ) )
        {
            const Symbol& t = ing.symbols[ n ];
            if( n != typeIds[ k ] && t.name == ing.symbols[ typeIds[ k ] ].name && ( t.kind == SymKind::Class || t.kind == SymKind::Struct || t.kind == SymKind::Interface ) )
            {
                namesakeFiles[ k ].push_back( t.fileId );
            }
        }
    }
    if( !typeIds.empty() )
    {
        for( const Symbol& s : ing.symbols )
        {
            if( ( s.kind != SymKind::Method && s.kind != SymKind::Function ) || s.scope.empty() )
            {
                continue;
            }
            for( std::size_t k = 0; k < typeIds.size(); ++k )
            {
                const bool otherType = s.fileId != ing.symbols[ typeIds[ k ] ].fileId && std::ranges::find( namesakeFiles[ k ], s.fileId ) != namesakeFiles[ k ].end();
                if( !otherType && s.lang == ing.symbols[ typeIds[ k ] ].lang && aliashop_detail::scopeEndsWith( s, typeScopes[ k ] ) )
                {
                    std::vector<std::string>& names = memberNames[ k ];
                    if( std::ranges::find( names, s.name ) == names.end() )
                    {
                        ++memberCount[ k ];
                        if( names.size() < kAliasHopMemberNames )
                        {
                            names.push_back( s.name );
                        }
                    }
                }
            }
        }
    }
    out.append( kAliasHopLegend ).append( "<aliases" );
    num( "total", walks.size() );
    num( "shown", shown );
    out.append( walks.size() > shown ? " capped=\"1\">" : " capped=\"0\">" );
    std::string        scratch;
    std::uint32_t      textOf = kNoFile;
    const std::string* text   = nullptr;
    for( std::size_t w = 0; w < shown; ++w )
    {
        const AliasHopChain& c  = walks[ w ].chain;
        const Symbol&        as = ing.symbols[ c.alias ];
        out.append( "<chain" );
        attr( "of", as.name );
        attr( "p", rootRelPath( ing, as.fileId ) );
        num( "l", as.line );
        if( const AliasTargetText t = aliasTargetText( ing, as ); t.has && !t.unread )
        {
            attr( "to", t.text );
        }
        if( walks[ w ].also > 0 )
        {
            num( "also", walks[ w ].also );
        }
        NodeId usersOf = kNoNode;   // the last type the chain reaches: whose users next= lists
        for( const AliasHopStep& st : c.steps )
        {
            usersOf = std::ranges::find( typeIds, st.def ) != typeIds.end() ? st.def : usersOf;
        }
        out.append( c.cycle ? " cycle=\"1\"" : "" ).append( c.capped ? " depth_capped=\"1\"" : "" );
        if( usersOf != kNoNode )
        {
            out.append( nextAttrXml( nextFlag( "--uses=", ing.symbols[ usersOf ].name ) ) );
        }
        out.append( ">" );
        for( const AliasHopStep& st : c.steps )
        {
            const Symbol& s = ing.symbols[ st.def ];
            out.append( "<h" );
            attr( "n", s.name );
            if( !s.scope.empty() && s.scope != s.name )   // a C++ type's scope is its own name: no sc= that says nothing
            {
                attr( "sc", s.scope );
            }
            attr( "t", symTag( s.kind ) );
            attr( "p", rootRelPath( ing, s.fileId ) );
            num( "l", s.line );
            num( "d", st.depth );
            out.append( " via=\"alias\"" ).append( st.arg ? " arg=\"1\"" : "" );
            if( st.cands > 1 )
            {
                num( "cands", st.cands );
            }
            if( const auto k = std::ranges::find( typeIds, st.def ); k != typeIds.end() )
            {
                const std::size_t ki = std::size_t( k - typeIds.begin() );
                num( "members", memberCount[ ki ] );
                if( !memberNames[ ki ].empty() )
                {
                    std::string m;
                    for( const std::string& n : memberNames[ ki ] )
                    {
                        m.append( m.empty() ? "" : "," ).append( n );
                    }
                    attr( "m", m );
                }
            }
            bool              cutText = false, unreadText = false;
            const std::string decl    = aliashop_for_detail::declText( ing, s, scratch, textOf, text, cutText, unreadText );
            out.append( unreadText ? " unread=\"1\"" : "" ).append( cutText ? " cut=\"1\">" : ">" ).append( escapeXml( decl, esc ) ).append( "</h>" );
        }
        for( const std::string& l : c.leaves )
        {
            out.append( "<leaf" );
            attr( "n", l );
            out.append( "/>" );
        }
        out.append( "</chain>" );
    }
    return out.append( "</aliases>" );
}

}   // namespace rw
