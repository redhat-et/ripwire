#pragma once
// forselfhook.h — THE SELF HOOK of a --for answer (lane self-hook): a served Python override names WHERE its base classes reach it
// through `self` or `cls`.
//
// WHY. "What calls SessionMiddleware.process_request?" serves that method's body and no caller: the only call is
// `self.process_request(request)` in MiddlewareMixin.__call__, under `hasattr`, and the mixin defines no such method, so the resolver
// has nothing to bind it to. "Which get_handler runs for runserver?" serves both get_handler bodies and neither names
// Command.inner_run, which calls self.get_handler: the edge is proven to the BASE's definition, so `--callers` lists it there, and the
// subtoken route has no caller hop at all. The site is in the index both times; the answer never says it.
//
// WHAT. <selfhooks total= shown= capped=> after the dispatch hop and before the bodies, one <selfhook> per served override:
// n= p= the served method; overrides= op= the nearest base definition (tied=, abstract=) or hook=1 when no base defines it; defs= the
// definitions in the inheritance cone, test= of them on test paths (counted, never named); sites= shown= capped= next=; one
// <s n= p=file:line [recv=cls] [form=ref|getattr] [guarded=1]> per site, non-test first, nearest base first.
// Hedged by construction: nothing enters a reaches= set, a count or --impact, and no edge is added. The list says where the base can
// reach the method; only instances of this class get there.
//
// BASES. The proven implementors edges, plus the edge buildGraph never draws: a base clause spelled with a RENAMED import
// (`from m import Command as RunserverCommand`; class Command(RunserverCommand)), where no class has the written name so the map holds
// nothing. That one is read here, for this element only, from the import's own module path to the one class of that name in that one
// file; it enters no graph table (--lego keeps its answer).
//
// WHEN. A served Python method (an auto <bodies> body, a fold/slot body, or a member the task names of a class served whole) of a non-test class, whose name has two or more definitions
// in the inheritance cone of its class, with at least one site in a base class. The default regime and the XML dialect (the dispatch
// hop's posture). Bases are walked over PROVEN implementors edges only, so a namesake class (two `Command`s in two modules) never
// crosses; a by-name base leaves the walk short and the element silent, a floor rather than a guess.
// RIPWIRE_NO_SELF_HOOK (any value) turns it off — the A/B handle.

#include "crossref.h"        // crossref::wholeWordAt
#include "docparse.h"        // docparse::detail::readWholeFile — the one whole-file reader
#include "filter.h"          // isTestSymbol
#include "graph.h"
#include "memberowner.h"
#include "model.h"
#include "nextverb.h"
#include "receiverevidence.h"   // ReceiverEvidence::callableKind / classLike
#include "sarif.h"           // rootRelativeUri
#include "serialize.h"       // escapeXml, diskPath

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

// Runaway guards, not size targets: every row left out is counted (total=, sites=, capped="1") and next= lists the sites.
inline constexpr std::size_t kForSelfHookSiteRows   = 3;   // base-class sites per served method
inline constexpr std::size_t kForSelfHookMethodRows = 4;   // served methods per answer

inline bool forSelfHookOn()
{
    return std::getenv( "RIPWIRE_NO_SELF_HOOK" ) == nullptr;
}

inline constexpr std::string_view kForSelfHookLegend =
    "; selfhooks total= shown= capped=: served methods whose base classes reach them through self or cls, selfhook n= p= the served method, "
    "overrides= op= the nearest base definition (tied=K other bases at that depth define it too and the method resolution order decides, abstract=1 that definition "
    "raises NotImplementedError or is marked abstract), hook=1 no base class in this tree defines it, defs= definitions in the inheritance cone, test= of them on test paths, "
    "not named, sites= shown= capped=1 next= lists the rest, s n= p=file:line a site in a base class (recv=cls through cls, form=ref names it without calling, "
    "form=getattr by string, guarded=1 a hasattr or getattr on that name comes first in that function, its absence is no claim). A call through self reaches this override only "
    "for instances of this class and other subclasses may run their own: which one runs is unproven, never an edge";
inline constexpr std::string_view kForCompactSelfHookLegend =
    "; selfhooks total= shown= capped=: served methods reached through self or cls from a base class, selfhook n= p=, overrides= op= nearest base def (tied=K, abstract=1), hook=1 no base defines it, "
    "defs= in the cone, test= not named, sites= shown= capped=1 next=, s n= p=file:line the base site (recv=cls, form=ref|getattr, guarded=1). Reaches this override only for its own instances, "
    "other subclasses may run theirs: never an edge";
static_assert( kForSelfHookLegend.find( ';', 1 ) == std::string_view::npos && kForCompactSelfHookLegend.find( ';', 1 ) == std::string_view::npos
                   && kForSelfHookLegend.find( "--" ) == std::string_view::npos && kForCompactSelfHookLegend.find( "--" ) == std::string_view::npos,
               "one clause each, and no \"--\": it rides inside an XML comment" );

namespace selfhook_detail
{
// The mechanism's family rows (CONTRIBUTING "Family rows"): the languages whose methods call their overrides through a receiver spelled
// in the source, and how that spelling reads. A language without a row carries no element.
struct FamilyRow
{
    Lang             lang;
    std::string_view memberImportMark;   // a Binding's importedName prefix for a member import; the member follows it
    std::string_view selfRecv;    // the instance receiver, recorded as RecvKind::ThisObj
    std::string_view classRecv;   // the class receiver, a plain name: it counts only as the caller's first parameter
    std::string_view probe;       // true when the object has the attribute, the name in a string
    std::string_view fetch;       // the attribute by string
    std::string_view defKeyword;
    std::string_view abstractRaise;
    std::string_view abstractMark;
};
inline constexpr FamilyRow kFamilyRows[] = {
    { Lang::Python, kPythonFromMemberMark, "self", "cls", "hasattr", "getattr", "def ", "NotImplementedError", "abstractmethod" },
};
inline const FamilyRow* familyRow( Lang l ) noexcept
{
    const auto* row = std::ranges::find( kFamilyRows, l, &FamilyRow::lang );
    return row == std::end( kFamilyRows ) ? nullptr : row;
}

// The text of `at`'s line before it (npos + 1 is the file's first line).
inline std::string_view linePrefix( std::string_view text, std::size_t at ) noexcept
{
    const std::string_view head = text.substr( 0, at );
    return head.substr( head.rfind( '\n' ) + 1 );
}
// The next non-space offset from `i`, text.size() when none is left.
inline std::size_t nextToken( std::string_view text, std::size_t i ) noexcept
{
    return std::min( text.find_first_not_of( " \t\r\n", i ), text.size() );
}

// `<fn>( <recv>, "<name>"` at a word boundary, from `from` on: the offsets of the matches (a commented-out line holds none).
inline std::vector<std::size_t> stringAttrUses( std::string_view text, std::string_view fn, std::string_view recv, std::string_view name )
{
    std::vector<std::size_t> out;
    for( std::size_t at = text.find( fn ); at != std::string_view::npos; at = text.find( fn, at + 1 ) )
    {
        if( !crossref::wholeWordAt( text, at, fn.size() ) )
        {
            continue;
        }
        std::size_t i = nextToken( text, at + fn.size() );
        if( i >= text.size() || text[i] != '(' )
        {
            continue;
        }
        i = nextToken( text, i + 1 );
        if( text.substr( i, recv.size() ) != recv )
        {
            continue;
        }
        i = nextToken( text, i + recv.size() );
        if( i >= text.size() || text[i] != ',' )
        {
            continue;
        }
        i = nextToken( text, i + 1 );
        if( i >= text.size() || ( text[i] != '"' && text[i] != '\'' ) )
        {
            continue;
        }
        const char quote = text[i];
        if( text.substr( i + 1, name.size() ) == name && i + 1 + name.size() < text.size() && text[ i + 1 + name.size() ] == quote && !linePrefix( text, at ).contains( '#' ) )
        {
            out.push_back( at );
        }
    }
    return out;
}

// The classes of the family's languages by file, for the class whose span holds a member.
class ClassIndex
{
public:
    explicit ClassIndex( const IngestResult& ing ) : m_ing( ing )
    {
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            const Symbol& s = ing.symbols[id];
            if( ReceiverEvidence::classLike( s.kind ) && s.endByte > s.sigStartByte && familyRow( s.lang ) != nullptr )
            {
                m_classes.push_back( id );
            }
        }
        std::ranges::sort( m_classes, [ & ]( NodeId a, NodeId b ) { return keyOf( a ) < keyOf( b ); } );
    }
    // The innermost class whose span holds `m`, kNoNode when none does.
    NodeId ownerOf( const Symbol& m ) const
    {
        const auto lower = std::ranges::lower_bound( m_classes, m.fileId, {}, [ & ]( NodeId c ) { return m_ing.symbols[c].fileId; } );
        NodeId     best  = kNoNode;
        for( auto it = lower; it != m_classes.end() && m_ing.symbols[ *it ].fileId == m.fileId && m_ing.symbols[ *it ].sigStartByte <= m.sigStartByte; ++it )
        {
            if( m_ing.symbols[ *it ].id != m.id && m.endByte <= m_ing.symbols[ *it ].endByte )
            {
                best = *it;   // ascending start: a later class that still holds the member is nested inside the earlier one
            }
        }
        return best;
    }

private:
    std::pair<std::uint32_t, std::uint32_t> keyOf( NodeId c ) const { return { m_ing.symbols[c].fileId, m_ing.symbols[c].sigStartByte }; }
    const IngestResult& m_ing;
    std::vector<NodeId> m_classes;
};

// A base class and its distance from the served method's class: 1 for a direct base.
struct Ancestor
{
    NodeId        id    = kNoNode;
    std::uint32_t depth = 0;
};
inline bool provenEdge( const Graph& g, NodeId base, std::size_t childIx ) noexcept
{
    return base < g.implementorBound.size() && childIx < g.implementorBound[ base ].size() && g.implementorBound[ base ][ childIx ] == static_cast<std::uint8_t>( BaseBound::Proven );
}
// `a.b.c` from `dir/x.py` (a leading dot climbs from the file's directory) to the ONE indexed file it names, kNoFile for none or several.
inline std::uint32_t moduleFileOf( const IngestResult& ing, std::string_view module, std::uint32_t fromFile )
{
    std::string stem;
    bool        relative = false;
    if( module.starts_with( '.' ) )
    {
        relative = true;
        stem     = rootRelPath( ing, fromFile );
        for( ; module.starts_with( '.' ); module.remove_prefix( 1 ) )
        {
            const std::size_t slash = stem.rfind( '/' );
            stem.resize( slash == std::string::npos ? 0 : slash );
        }
        if( !stem.empty() )
        {
            stem += '/';
        }
    }
    for( const char c : module )
    {
        stem += c == '.' ? '/' : c;
    }
    std::uint32_t found = kNoFile;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view path = rootRelPath( ing, f );
        for( const std::string_view tail : { std::string_view( ".py" ), std::string_view( "/__init__.py" ) } )
        {
            const bool whole = path.size() == stem.size() + tail.size();
            if( !path.ends_with( tail ) || path.size() < stem.size() + tail.size() || path.substr( path.size() - tail.size() - stem.size(), stem.size() ) != stem
                || ( relative && !whole ) || ( !whole && path[ path.size() - tail.size() - stem.size() - 1 ] != '/' ) )
            {
                continue;
            }
            if( found != kNoFile && found != f )
            {
                return kNoFile;
            }
            found = f;
        }
    }
    return found;
}
// The (derived, base) edges a renamed import states (see BASES above): one binding of the written name in the file, one module file, one
// module-level class of the member's name there. Any second reading leaves the edge out: a floor.
inline void addRenamedImportBases( const IngestResult& ing, std::vector<std::pair<NodeId, NodeId>>& edges )
{
    struct Renamed
    {
        std::uint32_t    file;
        std::string_view var;
        std::string_view member;
        std::string_view module;
    };
    std::vector<Renamed> renamed;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind != LocalBindKind::Import || b.fromSymbol != kNoNode || b.importedName == "module" )
        {
            continue;
        }
        const std::string_view imported = b.importedName;
        for( const FamilyRow& row : kFamilyRows )
        {
            if( imported.starts_with( row.memberImportMark ) && imported.substr( row.memberImportMark.size() ) != b.var )
            {
                renamed.push_back( Renamed{ b.fileId, b.var, imported.substr( row.memberImportMark.size() ), b.typeName } );
            }
        }
    }
    if( renamed.empty() )
    {
        return;
    }
    const auto key = []( const Renamed& r ) { return std::pair( r.file, r.var ); };
    std::ranges::sort( renamed, [ & ]( const Renamed& a, const Renamed& b ) { return key( a ) < key( b ); } );
    for( const Reference& r : ing.references )
    {
        if( !r.isInherit || !r.memberRoot.empty() || r.fromSymbol >= ing.symbols.size() || familyRow( r.lang ) == nullptr )
        {
            continue;
        }
        const auto hit = std::ranges::equal_range( renamed, std::pair( r.fileId, std::string_view( r.calleeName ) ), {}, key );
        if( hit.size() != 1 )
        {
            continue;
        }
        const std::uint32_t file = moduleFileOf( ing, hit.front().module, r.fileId );
        if( file == kNoFile )
        {
            continue;
        }
        NodeId base  = kNoNode;
        bool   twice = false;
        for( NodeId c = 0; c < ing.symbols.size(); ++c )
        {
            const Symbol& s = ing.symbols[c];
            if( s.fileId == file && s.name == hit.front().member && ReceiverEvidence::classLike( s.kind ) )
            {
                twice = twice || base != kNoNode;
                base  = c;
            }
        }
        if( base != kNoNode && !twice )
        {
            edges.emplace_back( r.fromSymbol, base );
        }
    }
}
// Every (child, base) edge the index proves, ascending: buildGraph binds a base NAME to every same-named class, so a by-name edge is exactly
// the namesake crossing this element must not make.
inline std::vector<std::pair<NodeId, NodeId>> provenParents( const IngestResult& ing, const Graph& g )
{
    std::vector<std::pair<NodeId, NodeId>> out;
    for( NodeId base = 0; base < g.implementors.size(); ++base )
    {
        for( std::size_t i = 0; i < g.implementors[ base ].size(); ++i )
        {
            if( provenEdge( g, base, i ) )
            {
                out.emplace_back( g.implementors[ base ][ i ], base );
            }
        }
    }
    addRenamedImportBases( ing, out );
    std::ranges::sort( out );
    return out;
}
// Breadth-first up the proven edges from `cls`, each base once at its shallowest depth; `cls` itself is never listed.
inline std::vector<Ancestor> ancestorsOf( std::span<const std::pair<NodeId, NodeId>> parents, NodeId cls )
{
    std::vector<Ancestor> out;
    const auto            seen = [ & ]( NodeId id ) { return id == cls || std::ranges::any_of( out, [ id ]( const Ancestor& a ) { return a.id == id; } ); };
    const auto            expand = [ & ]( NodeId child, std::uint32_t depth )
    {
        const auto range = std::ranges::equal_range( parents, child, {}, []( const std::pair<NodeId, NodeId>& e ) { return e.first; } );
        for( const auto& edge : range )
        {
            if( !seen( edge.second ) )
            {
                out.push_back( Ancestor{ edge.second, depth } );
            }
        }
    };
    expand( cls, 1 );
    for( std::size_t i = 0; i < out.size(); ++i )   // out grows inside the loop: index, never iterate by reference
    {
        expand( out[i].id, out[i].depth + 1 );
    }
    return out;
}
// The classes at or below any of `roots`, over proven edges: the inheritance cone. One byte per symbol, so a membership test is one load.
inline std::vector<char> coneOf( std::span<const std::pair<NodeId, NodeId>> parents, std::size_t symbolCount, std::span<const NodeId> roots )
{
    std::vector<char> in( symbolCount, char( 0 ) );
    for( const NodeId r : roots )
    {
        in[r] = 1;
    }
    // edges sorted by child, so a downward walk is a fixpoint over them: a pass that marks nothing ends it
    for( bool grew = true; grew; )
    {
        grew = false;
        for( const auto& [ child, base ] : parents )
        {
            if( in[base] != 0 && in[child] == 0 )
            {
                in[child] = 1;
                grew      = true;
            }
        }
    }
    return in;
}

// One file's bytes, the last one read kept: the sites of one method sit in few files.
class SourceReader
{
public:
    explicit SourceReader( const IngestResult& ing ) : m_ing( ing ) {}
    // A symbol's text, "" when the file cannot be read or has changed under the span: a guard is then not said, which claims nothing.
    std::string_view textOf( const Symbol& s )
    {
        if( !m_have || m_file != s.fileId )
        {
            m_have  = true;
            m_file  = s.fileId;
            m_bytes = docparse::detail::readWholeFile( diskPath( m_ing, s.fileId ) );
        }
        if( !m_bytes.has_value() || s.endByte > m_bytes->size() || s.sigStartByte >= s.endByte )
        {
            return {};
        }
        return std::string_view( *m_bytes ).substr( s.sigStartByte, s.endByte - s.sigStartByte );
    }

    // The 1-based line of offset `at` in textOf( s ): counted from the file, because a decorated definition's span starts above Symbol::line.
    std::uint32_t lineOf( const Symbol& s, std::size_t at ) const
    {
        return 1 + static_cast<std::uint32_t>( std::ranges::count( std::string_view( *m_bytes ).substr( 0, s.sigStartByte + at ), '\n' ) );
    }

private:
    const IngestResult&        m_ing;
    bool                       m_have = false;
    std::uint32_t              m_file = 0;
    std::optional<std::string> m_bytes;
};

enum class SiteForm : std::uint8_t { Call, Ref, Getattr };
struct Site
{
    NodeId        caller  = kNoNode;
    std::uint32_t line    = 0;
    std::uint32_t depth   = 0;
    SiteForm      form    = SiteForm::Call;
    bool          viaCls  = false;
    bool          guarded = false;
    bool          test    = false;
};

// A call or reference through the class receiver counts only in a function whose FIRST parameter it is: `cls = pick(); cls.run()` is a local.
inline bool firstParamIs( std::string_view text, const FamilyRow& row, std::string_view param )
{
    const std::size_t def = text.find( row.defKeyword );
    const std::size_t par = def == std::string_view::npos ? def : text.find( '(', def );
    if( par == std::string_view::npos )
    {
        return false;
    }
    const std::size_t i = nextToken( text, par + 1 );
    return text.substr( i, param.size() ) == param && crossref::wholeWordAt( text, i, param.size() );
}
inline bool guardedBefore( std::string_view text, const FamilyRow& row, std::string_view recv, std::string_view name, std::size_t site )
{
    const auto before = [ site ]( std::size_t at ) { return at < site; };
    return std::ranges::any_of( stringAttrUses( text, row.probe, recv, name ), before ) || std::ranges::any_of( stringAttrUses( text, row.fetch, recv, name ), before );
}
inline void orderSites( std::vector<Site>& sites, const IngestResult& ing )
{
    const auto key = [ & ]( const Site& s ) { return std::tuple( s.test, s.depth, ing.symbols[ s.caller ].fileId, s.line, s.form ); };
    std::ranges::sort( sites, [ & ]( const Site& a, const Site& b ) { return key( a ) < key( b ); } );
    const auto dup = std::ranges::unique( sites, [ & ]( const Site& a, const Site& b ) { return a.caller == b.caller && a.line == b.line && a.form == b.form; } );
    sites.erase( dup.begin(), dup.end() );
}
struct Finder
{
    const IngestResult& ing;
    const ClassIndex&   classes;
    SourceReader&       source;

    std::optional<std::uint32_t> depthOf( std::span<const Ancestor> bases, const Symbol& caller ) const
    {
        const NodeId owner = classes.ownerOf( caller );
        const auto   it    = std::ranges::find( bases, owner, &Ancestor::id );
        return it == bases.end() ? std::nullopt : std::optional<std::uint32_t>( it->depth );
    }
    void addRef( std::vector<Site>& out, const Reference& r, std::span<const Ancestor> bases, const FamilyRow& row, std::string_view name )
    {
        if( r.fromSymbol == kNoNode || r.fromSymbol >= ing.symbols.size() || r.calleeName != name || r.lang != row.lang
            || ( r.role != RefRole::Call && r.role != RefRole::Read ) )
        {
            return;
        }
        const bool throughSelf = r.recv == RecvKind::ThisObj;
        if( !throughSelf && !( r.recv == RecvKind::NamedVar && r.recvVar == row.classRecv ) )
        {
            return;
        }
        const Symbol&                      caller = ing.symbols[ r.fromSymbol ];
        const std::optional<std::uint32_t> depth  = depthOf( bases, caller );
        if( !depth.has_value() )
        {
            return;
        }
        const std::string_view text = source.textOf( caller );
        if( !throughSelf && !firstParamIs( text, row, row.classRecv ) )
        {
            return;
        }
        const std::size_t offset = r.startByte >= caller.sigStartByte ? r.startByte - caller.sigStartByte : text.size();
        out.push_back( Site{ r.fromSymbol, r.line, *depth, r.role == RefRole::Call ? SiteForm::Call : SiteForm::Ref, !throughSelf,
                             guardedBefore( text, row, throughSelf ? row.selfRecv : row.classRecv, name, offset ), isTestSymbol( ing, r.fromSymbol ) } );
    }
    std::vector<Site> sitesOf( std::span<const Ancestor> bases, const FamilyRow& row, std::string_view name )
    {
        std::vector<Site> out;
        for( const Reference& r : ing.references )
        {
            addRef( out, r, bases, row, name );
        }
        for( NodeId s = 0; s < ing.symbols.size(); ++s )
        {
            addFetches( out, s, bases, row, name );
        }
        orderSites( out, ing );
        return out;
    }
    // A fetch by string leaves no reference, so the bases' own functions are read for it.
    void addFetches( std::vector<Site>& out, NodeId id, std::span<const Ancestor> bases, const FamilyRow& row, std::string_view name )
    {
        const Symbol& s = ing.symbols[id];
        if( s.lang != row.lang || !ReceiverEvidence::callableKind( s.kind ) )
        {
            return;
        }
        const std::optional<std::uint32_t> depth = depthOf( bases, s );
        if( !depth.has_value() )
        {
            return;
        }
        const std::string_view text = source.textOf( s );
        for( const std::size_t at : stringAttrUses( text, row.fetch, row.selfRecv, name ) )
        {
            out.push_back( Site{ id, source.lineOf( s, at ), *depth, SiteForm::Getattr, false, true, isTestSymbol( ing, id ) } );
        }
    }
};

// A whole class in the served list carries its methods' text: the ones the task spells count as served, the rest are the class's bulk.
inline std::vector<NodeId> withTaskNamedMembers( const IngestResult& ing, const ClassIndex& classes, std::span<const NodeId> served, std::string_view task )
{
    std::vector<NodeId> out( served.begin(), served.end() );
    const auto          inTask = [ task ]( std::string_view name )
    {
        for( std::size_t at = task.find( name ); at != std::string_view::npos; at = task.find( name, at + 1 ) )
        {
            if( crossref::wholeWordAt( task, at, name.size() ) )
            {
                return true;
            }
        }
        return false;
    };
    const auto isServedClass = [ & ]( NodeId id ) { return id < ing.symbols.size() && ReceiverEvidence::classLike( ing.symbols[id].kind ) && familyRow( ing.symbols[id].lang ) != nullptr; };
    if( std::ranges::none_of( served, isServedClass ) )
    {
        return out;
    }
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( ReceiverEvidence::callableKind( s.kind ) && !s.fnLocal && familyRow( s.lang ) != nullptr && inTask( s.name ) )
        {
            const NodeId owner = classes.ownerOf( s );
            if( owner != kNoNode && std::ranges::find( served, owner ) != served.end() )
            {
                out.push_back( id );
            }
        }
    }
    return out;
}

}   // namespace selfhook_detail

struct SelfHookInputs
{
    const IngestResult& ing;
    const Graph&        g;
    std::string_view    rootArg;
    std::string_view    task;
};

namespace selfhook_detail
{
// The definitions of a method's name in its inheritance cone: never a namesake's. nearest = the closest base definition, tied = others at its depth.
struct ConeDefs
{
    std::size_t   defs     = 0;
    std::size_t   testDefs = 0;
    NodeId        nearest  = kNoNode;
    std::uint32_t depth    = 0;
    std::size_t   tied     = 0;
};
inline ConeDefs coneDefsOf( const IngestResult& ing, const ClassIndex& classes, std::span<const std::pair<NodeId, NodeId>> parents, const Symbol& m, NodeId cls, std::span<const Ancestor> bases )
{
    std::vector<NodeId> roots{ cls };
    for( const Ancestor& a : bases )
    {
        roots.push_back( a.id );
    }
    const std::vector<char> cone = coneOf( parents, ing.symbols.size(), roots );
    ConeDefs                out;
    for( NodeId d = 0; d < ing.symbols.size(); ++d )
    {
        const Symbol& def = ing.symbols[d];
        if( def.name != m.name || def.lang != m.lang || def.fnLocal || !ReceiverEvidence::callableKind( def.kind ) )
        {
            continue;
        }
        const NodeId owner = classes.ownerOf( def );
        if( owner == kNoNode || cone[ owner ] == 0 )
        {
            continue;
        }
        ++out.defs;
        out.testDefs += isTestSymbol( ing, d ) ? 1u : 0u;
        const auto base = std::ranges::find( bases, owner, &Ancestor::id );
        if( base == bases.end() )
        {
            continue;
        }
        if( out.nearest == kNoNode || base->depth < out.depth )
        {
            out.nearest = d;
            out.depth   = base->depth;
            out.tied    = 0;
        }
        else if( base->depth == out.depth )
        {
            ++out.tied;
        }
    }
    return out;
}

// One answer's rendering state: the row writers read it, and it lives as long as the element.
struct RowWriter
{
    const IngestResult& ing;
    const MemberOwners& owners;
    std::string_view    rootArg;
    SourceReader&       source;
    std::vector<char>   esc;

    std::string siteOf( std::uint32_t fileId, std::uint32_t line )
    {
        const std::string_view rel = rootArg.empty() ? std::string_view( ing.files[ fileId ] ) : sarif::rootRelativeUri( ing.files[ fileId ], rootArg );
        return std::string( escapeXml( rel, esc ) ) + ':' + std::to_string( line );
    }
    void relation( std::string& x, const ConeDefs& d, const FamilyRow& row )
    {
        if( d.nearest == kNoNode )
        {
            x += " hook=\"1\"";
            return;
        }
        const Symbol& base = ing.symbols[ d.nearest ];
        x += " overrides=\"";
        x += escapeXml( qualifiedMemberName( owners, base ), esc );
        x += "\" op=\"" + siteOf( base.fileId, base.line ) + '"';
        if( d.tied > 0 )
        {
            x += " tied=\"" + std::to_string( d.tied ) + '"';
        }
        const std::string_view text = source.textOf( base );
        if( text.find( row.abstractRaise ) != std::string_view::npos || text.find( row.abstractMark ) != std::string_view::npos )
        {
            x += " abstract=\"1\"";
        }
    }
    void siteRow( std::string& x, const Site& site )
    {
        const Symbol& caller = ing.symbols[ site.caller ];
        x += "<s n=\"";
        x += escapeXml( qualifiedMemberName( owners, caller ), esc );
        x += "\" p=\"" + siteOf( caller.fileId, site.line ) + '"';
        if( site.viaCls )
        {
            x += " recv=\"cls\"";
        }
        if( site.form != SiteForm::Call )
        {
            x += site.form == SiteForm::Ref ? " form=\"ref\"" : " form=\"getattr\"";
        }
        if( site.guarded )
        {
            x += " guarded=\"1\"";
        }
        x += "/>";
    }
    void method( std::string& x, const Symbol& m, const ConeDefs& d, const FamilyRow& row, std::span<const Site> sites )
    {
        const std::size_t siteRows = std::min( sites.size(), kForSelfHookSiteRows );
        const std::string qual( qualifiedMemberName( owners, m ) );
        x += "<selfhook n=\"";
        x += escapeXml( qual, esc );
        x += "\" p=\"" + siteOf( m.fileId, m.line ) + '"';
        relation( x, d, row );
        x += " defs=\"" + std::to_string( d.defs ) + '"';
        if( d.testDefs > 0 )
        {
            x += " test=\"" + std::to_string( d.testDefs ) + '"';
        }
        x += " sites=\"" + std::to_string( sites.size() ) + "\" shown=\"" + std::to_string( siteRows ) + "\" capped=\"" + ( siteRows < sites.size() ? "1" : "0" ) + '"';
        if( siteRows < sites.size() )
        {
            x += nextAttrXml( nextFlag( "--callers=", qual ) );
        }
        x += '>';
        for( const Site& site : sites.first( siteRows ) )
        {
            siteRow( x, site );
        }
        x += "</selfhook>";
    }
};
}   // namespace selfhook_detail

// The element for `served`, "" when no served method qualifies (see WHEN above). A method served twice counts once.
inline std::string renderForSelfHooks( const SelfHookInputs& in, std::span<const NodeId> served )
{
    using namespace selfhook_detail;
    const IngestResult& ing = in.ing;
    if( std::ranges::none_of( served, [ & ]( NodeId id ) { return id < ing.symbols.size() && familyRow( ing.symbols[id].lang ) != nullptr; } ) )
    {
        return {};
    }
    const ClassIndex   classes( ing );
    const auto         parents = provenParents( ing, in.g );
    const MemberOwners owners( ing );
    SourceReader       source( ing );
    Finder             finder{ ing, classes, source };
    RowWriter          writer{ ing, owners, in.rootArg, source, {} };

    std::vector<NodeId> seen;
    std::string         rows;
    std::size_t         total = 0;
    std::size_t         shown = 0;
    for( const NodeId id : withTaskNamedMembers( ing, classes, served, in.task ) )
    {
        if( id >= ing.symbols.size() || std::ranges::find( seen, id ) != seen.end() )
        {
            continue;
        }
        seen.push_back( id );
        const Symbol&    m   = ing.symbols[id];
        const FamilyRow* row = familyRow( m.lang );
        if( row == nullptr || !ReceiverEvidence::callableKind( m.kind ) || m.fnLocal || isTestSymbol( ing, id ) )
        {
            continue;
        }
        const NodeId                cls   = classes.ownerOf( m );
        const std::vector<Ancestor> bases = cls == kNoNode ? std::vector<Ancestor>{} : ancestorsOf( parents, cls );
        if( bases.empty() )
        {
            continue;
        }
        const std::vector<Site> sites = finder.sitesOf( bases, *row, m.name );
        if( sites.empty() )
        {
            continue;
        }
        const ConeDefs defs = coneDefsOf( ing, classes, parents, m, cls, bases );
        if( defs.defs < 2 )
        {
            continue;   // no override relation: the caller hop's question, not this one
        }
        ++total;
        if( shown < kForSelfHookMethodRows )
        {
            ++shown;
            writer.method( rows, m, defs, *row, sites );
        }
    }
    if( rows.empty() )
    {
        return {};
    }
    return "<selfhooks total=\"" + std::to_string( total ) + "\" shown=\"" + std::to_string( shown ) + "\" capped=\"" + ( shown < total ? "1" : "0" ) + "\">" + rows + "</selfhooks>";
}

}   // namespace rw
