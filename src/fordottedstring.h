#pragma once
// fordottedstring.h — STRING-IMPORT: the dotted-string literals that name a shown Python definition.
//
// WHY. `import_string( path )` loads what a string names, so no call edge reaches the target: `_builtin_context_processors =
// ("django.template.context_processors.csrf",)` is why `csrf` runs on every render, and a name search or a --callers finds no
// trace of that (ORCH reports/ld2-baseline.md: django-13).
//
// WHAT. <dotted_strings> with one <ds> row per literal SITE whose whole value resolves (pydottedpath.h: its module file, then
// exactly one definition in it; or a module itself) to a row this answer shows: the string (s=), the target (tn= tp=, or mod=),
// where the string sits (p= l= in=), and how it may be loaded: sink= when the string is that sink's own argument, else
// loader= lp= for a function that names the constant and calls an import sink. A `%`-template handed to a sink
// (`"%s.base" % x`) gets one hedged row when the directories of at least two shown files fill its hole: cand= those modules, cands=
// how many; which one loads is not known.
//
// HONESTY. A string in the source names this symbol; whether it reaches the sink is NOT traced, so nothing here enters reaches=,
// counts or --impact, and no edge exists. A string resolves through its whole path, never a bare name; the last-segment
// comparison is only a pre-filter. Its module missing (external=) or the name not exactly one definition there (unresolved=)
// prints no target, only a count. A test path's site is counted (tests=), never a row. The parser decides which strings are facts
// (ingest_valuerefs.h dottedStringAt): docstrings, log arguments and dict keys record nothing.
//
// WHEN. The default regime of --for (XML, no --token-budget) and --callers, after every byte of the ordinary answer and outside
// est_tokens: RIPWIRE_NO_DOTTED_STRINGS=1 is the rest of it byte for byte.

#include "docparse.h"       // docparse::detail::readWholeFile
#include "filter.h"         // isTestPath
#include "model.h"
#include "pydottedpath.h"
#include "serialize.h"      // escapeXml
#include "taskroute.h"      // taskroute::wordByte

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <map>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t kForDottedStringRows = 3;   // <ds> rows per answer (capped=1 next= beyond it)
inline constexpr std::size_t kForDottedTemplateMinFills = 2;      // distinct shown directories that must fill a %-template's hole
inline constexpr std::size_t kForDottedTemplateFillsListed = 4;   // modules listed in cand= (cands= counts all that shown directories fill)

inline bool forDottedStringsOn()
{
    return std::getenv( "RIPWIRE_NO_DOTTED_STRINGS" ) == nullptr;
}

inline constexpr std::string_view kForDottedStringsLegend =
    "<!-- ripwire for dotted_strings: Python string literals whose whole dotted path names a shown row; hedge= is the whole "
    "claim: no edge, not in est_tokens or any count. ds s= the string; "
    "tn= tp= the definition it names, or mod= the module; p= l= in= where the string sits; sink= it is that import call's argument; "
    "loader= lp= a function naming that constant and calling an import sink (loaders= how many do, by name, a floor); tmpl= a %-template "
    "passed to a sink, cand= modules that directories of shown files would fill it with, cands= how many, which one loads is not known. sites= non-test sites, rows= printed; "
    "tests= sites in test paths, counted only; unresolved= external= strings ending in a shown name that resolve to no one definition, "
    "or to no in-tree module; rows_capped=1 next= the list was cut. -->";

struct DottedTarget
{
    enum class State : std::uint8_t { External, Unresolved, Def, Module };
    State         state = State::External;
    NodeId        def   = kNoNode;
    std::uint32_t file  = kNoFile;
};

namespace dotteddetail
{

// One pass per file over its symbols, memoised: a file's attribute lookups repeat across the strings of one package.
struct SymbolsOfFile
{
    std::map<std::uint32_t, std::vector<NodeId>> byFile;
    explicit SymbolsOfFile( const IngestResult& ing, const std::set<std::uint32_t>& files )
    {
        for( NodeId id = 0; id < ing.symbols.size(); ++id )
        {
            if( files.contains( ing.symbols[id].fileId ) )
            {
                byFile[ ing.symbols[id].fileId ].push_back( id );
            }
        }
    }
};

inline std::string displayName( const Symbol& s )
{
    return s.scope.empty() || s.scope == s.name ? s.name : s.scope + "." + s.name;
}

// `a.b.c` with the module file of its longest importable prefix. Ambiguity (`a.b` both a module and a name in `a`) names nothing.
struct ModuleSplit
{
    DottedTarget::State state = DottedTarget::State::External;
    std::uint32_t       wholeFile = kNoFile;   // the whole string is this module
    std::uint32_t       file = kNoFile;        // the prefix module holding the attribute
    std::string_view    attr;
};
inline ModuleSplit splitDotted( const IngestResult& ing, std::string_view lit )
{
    ModuleSplit out;
    bool        inTree = false;
    out.wholeFile = epModuleFile( ing, {}, lit, inTree );
    bool anyTree = inTree;
    for( std::size_t dot = lit.rfind( '.' ); dot != std::string_view::npos && dot > 0; dot = lit.rfind( '.', dot - 1 ) )
    {
        inTree = false;
        const std::uint32_t f = epModuleFile( ing, {}, lit.substr( 0, dot ), inTree );
        anyTree = anyTree || inTree;
        if( f != kNoFile )
        {
            out.file = f;
            out.attr = lit.substr( dot + 1 );
            break;   // the longest importable prefix is the module the sink would load
        }
        if( inTree )
        {
            break;   // that module exists only at a deeper or doubled path: which file it is is not known
        }
    }
    out.state = anyTree ? DottedTarget::State::Unresolved : DottedTarget::State::External;
    return out;
}

// The last path component a dotted module spelling would end in, for the pre-filter: the stem, or the package of an __init__.py.
inline std::string_view moduleTailOf( std::string_view rel )
{
    const std::size_t slash = rel.rfind( '/' );
    std::string_view  base  = slash == std::string_view::npos ? rel : rel.substr( slash + 1 );
    if( base == "__init__.py" )
    {
        const std::string_view dir = slash == std::string_view::npos ? std::string_view() : rel.substr( 0, slash );
        const std::size_t      up  = dir.rfind( '/' );
        return up == std::string_view::npos ? dir : dir.substr( up + 1 );
    }
    return base.ends_with( ".py" ) ? base.substr( 0, base.size() - 3 ) : std::string_view();
}

inline bool holdsWord( std::string_view text, std::string_view word ) noexcept
{
    for( std::size_t at = text.find( word ); at != std::string_view::npos; at = text.find( word, at + 1 ) )
    {
        const bool leftOk  = at == 0 || !taskroute::wordByte( text[at - 1] );
        const bool rightOk = at + word.size() >= text.size() || !taskroute::wordByte( text[at + word.size()] );
        if( leftOk && rightOk )
        {
            return true;
        }
    }
    return false;
}

struct Row
{
    int              rankClass = 2;
    std::size_t      shownAt   = 0;
    const Reference* site      = nullptr;
    NodeId           targetDef = kNoNode;
    std::uint32_t    targetMod = kNoFile;
    std::string      candMod;      // a template row: the module file it would load
    std::size_t      cands = 0;
    NodeId           loader = kNoNode;
    std::size_t      loaders = 0;
};

inline void attr( std::string& x, std::string_view key, std::string_view val, std::vector<char>& esc )
{
    x += ' ';
    x += key;
    x += "=\"";
    x += escapeXml( val, esc );
    x += '"';
}

inline std::string siteInName( const IngestResult& ing, const Reference& r )
{
    const bool haveOwner = r.fromSymbol != kNoNode && r.fromSymbol < ing.symbols.size();
    if( r.memberCtor.empty() )
    {
        return haveOwner ? displayName( ing.symbols[ r.fromSymbol ] ) : std::string();
    }
    if( haveOwner && ing.symbols[ r.fromSymbol ].name != r.memberCtor )
    {
        return displayName( ing.symbols[ r.fromSymbol ] ) + "." + r.memberCtor;
    }
    return r.memberCtor;
}

// The template's fixed text around its one hole ("django.db.%s.base" → "django.db.", ".base"); nullopt unless exactly one %s.
inline std::optional<std::pair<std::string_view, std::string_view>> templateParts( std::string_view t )
{
    const std::size_t hole = t.find( "%s" );
    if( hole == std::string_view::npos || t.find( "%s", hole + 2 ) != std::string_view::npos || hole + 2 >= t.size() )
    {
        return std::nullopt;
    }
    return std::make_pair( t.substr( 0, hole ), t.substr( hole + 2 ) );
}

inline std::string dottedOfPath( std::string_view rel )
{
    std::string d( rel );
    std::ranges::replace( d, '/', '.' );
    return d;
}

}   // namespace dotteddetail

// The element for the shown rows `shown` (in answer order): "" when no dotted string names one. Reads the fact stream once, resolves
// only strings whose last segment matches a shown name, and reads a file only to confirm a loader of a printed candidate.
inline std::string renderDottedStrings( const IngestResult& ing, std::span<const NodeId> shown )
{
    using namespace dotteddetail;
    if( ing.crawlRoot.empty() || shown.empty() || !forDottedStringsOn() )
    {
        return {};
    }
    // the shown rows, by what a string could spell
    std::set<std::string_view>            wanted;
    std::map<NodeId, std::size_t>         shownDef;
    std::map<std::uint32_t, std::size_t>  shownFile;
    std::map<std::pair<std::uint32_t, std::string_view>, std::size_t> shownOwner;   // a method's class is what a string names
    for( std::size_t k = 0; k < shown.size(); ++k )
    {
        if( shown[k] >= ing.symbols.size() )
        {
            continue;
        }
        const Symbol&          s   = ing.symbols[ shown[k] ];
        const std::string_view rel = rootRelPath( ing, s.fileId );
        if( !rel.ends_with( ".py" ) )
        {
            continue;
        }
        shownDef.try_emplace( shown[k], k );
        shownFile.try_emplace( s.fileId, k );
        wanted.insert( s.name );
        wanted.insert( moduleTailOf( rel ) );
        if( !s.scope.empty() && s.scope != s.name )
        {
            const std::size_t      sep   = s.scope.find_last_of( ".:" );
            const std::string_view owner = sep == std::string::npos ? std::string_view( s.scope ) : std::string_view( s.scope ).substr( sep + 1 );
            wanted.insert( owner );
            shownOwner.try_emplace( std::make_pair( s.fileId, owner ), k );
        }
    }
    if( shownDef.empty() )
    {
        return {};
    }
    // the facts: candidates by last segment; the loaders; the templates
    std::vector<const Reference*> cand;
    std::vector<const Reference*> loaders;
    std::vector<const Reference*> templates;
    for( const Reference& r : ing.references )
    {
        if( r.role != RefRole::Value || r.qualifier.size() != 1 || r.qualifier[0] != kValueRefDottedStringScope )
        {
            continue;
        }
        if( r.composeRel == kDottedShapeVariable )
        {
            loaders.push_back( &r );
        }
        else if( r.composeRel == kDottedShapeFormat )
        {
            templates.push_back( &r );
        }
        else
        {
            const std::size_t dot = r.recvVar.rfind( '.' );
            if( dot != std::string::npos && wanted.contains( std::string_view( r.recvVar ).substr( dot + 1 ) ) )
            {
                cand.push_back( &r );
            }
        }
    }
    // resolve each distinct string once
    std::map<std::string_view, ModuleSplit> split;
    std::set<std::uint32_t>                 attrFiles;
    for( const Reference* r : cand )
    {
        const auto [ it, isNew ] = split.try_emplace( r->recvVar );
        if( isNew )
        {
            it->second = splitDotted( ing, r->recvVar );
            if( it->second.file != kNoFile )
            {
                attrFiles.insert( it->second.file );
            }
        }
    }
    const SymbolsOfFile                      syms( ing, attrFiles );
    std::map<std::string_view, DottedTarget> resolved;
    std::size_t                              unresolvedN = 0;
    std::size_t                              externalN   = 0;
    for( const auto& [ lit, sp ] : split )
    {
        DottedTarget t;
        t.state = sp.state;
        NodeId      def  = kNoNode;
        std::size_t hits = 0;
        if( sp.file != kNoFile )
        {
            if( const auto f = syms.byFile.find( sp.file ); f != syms.byFile.end() )
            {
                for( const NodeId id : f->second )
                {
                    if( epAttrNames( ing.symbols[id], sp.attr ) )
                    {
                        def = id;
                        ++hits;
                    }
                }
            }
        }
        if( sp.wholeFile != kNoFile && hits == 0 )
        {
            t = DottedTarget{ DottedTarget::State::Module, kNoNode, sp.wholeFile };
        }
        else if( sp.wholeFile == kNoFile && hits == 1 )
        {
            t = DottedTarget{ DottedTarget::State::Def, def, kNoFile };
        }
        else if( sp.wholeFile != kNoFile || hits > 1 || sp.file != kNoFile )
        {
            t.state = DottedTarget::State::Unresolved;   // both a module and a name, or not exactly one definition
        }
        unresolvedN += t.state == DottedTarget::State::Unresolved ? 1 : 0;
        externalN   += t.state == DottedTarget::State::External ? 1 : 0;
        resolved.emplace( lit, t );
    }
    // the sites whose target is a shown row
    std::vector<Row>                   rows;
    std::size_t                        testSites = 0;
    std::string_view                   firstTestString;
    std::set<std::pair<std::uint32_t, std::string>> seenSite;
    for( const Reference* r : cand )
    {
        const DottedTarget& t  = resolved.at( r->recvVar );
        std::size_t         at = 0;
        bool                hit = false;
        if( t.state == DottedTarget::State::Def )
        {
            const Symbol& target = ing.symbols[ t.def ];
            if( const auto d = shownDef.find( t.def ); d != shownDef.end() )
            {
                at  = d->second;
                hit = true;
            }
            else if( const auto o = shownOwner.find( std::make_pair( target.fileId, std::string_view( target.name ) ) ); target.kind == SymKind::Class && o != shownOwner.end() )
            {
                at  = o->second;
                hit = true;
            }
        }
        else if( t.state == DottedTarget::State::Module )
        {
            if( const auto f = shownFile.find( t.file ); f != shownFile.end() )
            {
                at  = f->second;
                hit = true;
            }
        }
        if( !hit || !seenSite.emplace( r->fileId, std::format( "{}:{}", r->line, r->recvVar ) ).second )
        {
            continue;
        }
        if( isTestPath( rootRelPath( ing, r->fileId ) ) )
        {
            ++testSites;
            if( firstTestString.empty() )
            {
                firstTestString = r->recvVar;
            }
            continue;
        }
        Row row;
        row.rankClass = r->composeRel == kDottedShapeSink ? 0 : t.state == DottedTarget::State::Def ? 4 : 5;
        row.shownAt   = at;
        row.site      = r;
        row.targetDef = t.def;
        row.targetMod = t.file;
        rows.push_back( row );
    }
    // a %-template handed to a sink, filled by the directories of shown files: at least kForDottedTemplateMinFills distinct ones (one
    // directory that happens to hold a base.py is a bare-name coincidence; several siblings is the plugin layout the template loads)
    for( const Reference* r : templates )
    {
        const auto parts = templateParts( r->recvVar );
        if( !parts || parts->second.empty() || isTestPath( rootRelPath( ing, r->fileId ) ) )
        {
            continue;
        }
        const auto [ pre, post ] = *parts;
        std::set<std::uint32_t> fills;
        std::size_t             firstShown = shown.size();
        for( const auto& [ fileId, at ] : shownFile )
        {
            const std::string_view rel = rootRelPath( ing, fileId );
            const std::size_t      sl  = rel.rfind( '/' );
            if( sl == std::string_view::npos )
            {
                continue;
            }
            const std::string dirMod = dottedOfPath( rel.substr( 0, sl ) );
            if( !dirMod.starts_with( pre ) || dirMod.size() == pre.size() || ( !pre.empty() && dirMod.find( '.', pre.size() ) != std::string::npos ) )
            {
                continue;   // the hole is one segment under a written prefix, a whole package path under none
            }
            bool                inTree = false;
            const std::uint32_t f      = epModuleFile( ing, {}, dirMod + std::string( post ), inTree );
            if( f != kNoFile && fills.insert( f ).second )
            {
                firstShown = std::min( firstShown, at );
            }
        }
        if( fills.size() < kForDottedTemplateMinFills )
        {
            continue;
        }
        Row row;
        row.rankClass = 2;
        row.shownAt   = firstShown;
        row.site      = r;
        row.cands     = fills.size();
        std::size_t listed = 0;
        for( const std::uint32_t f : fills )
        {
            if( listed++ < kForDottedTemplateFillsListed )
            {
                row.candMod += ( row.candMod.empty() ? "" : "," ) + std::string( rootRelPath( ing, f ) );
            }
        }
        rows.push_back( std::move( row ) );
    }
    if( rows.empty() && testSites == 0 )
    {
        return {};
    }
    // loaders of the constants: a non-test function that calls a sink on a computed value and names the constant
    std::map<NodeId, std::string> bodyOf;
    const auto                    bodyText = [ & ]( NodeId id ) -> const std::string&
    {
        const auto [ it, isNew ] = bodyOf.try_emplace( id );
        if( isNew )
        {
            const Symbol& s = ing.symbols[id];
            if( const std::optional<std::string> text = docparse::detail::readWholeFile( diskPath( ing, s.fileId ) ); text && s.sigStartByte < s.endByte && s.endByte <= text->size() )
            {
                it->second = text->substr( s.sigStartByte, s.endByte - s.sigStartByte );
            }
        }
        return it->second;
    };
    for( Row& row : rows )
    {
        if( row.site->memberCtor.empty() || row.site->composeRel == kDottedShapeSink || row.site->composeRel == kDottedShapeFormat )
        {
            continue;
        }
        std::set<NodeId> seen;
        for( const Reference* v : loaders )
        {
            if( v->fromSymbol >= ing.symbols.size() || isTestPath( rootRelPath( ing, v->fileId ) ) || !seen.insert( v->fromSymbol ).second )
            {
                continue;
            }
            if( holdsWord( bodyText( v->fromSymbol ), row.site->memberCtor ) )
            {
                ++row.loaders;
                if( row.loader == kNoNode || v->fileId == row.site->fileId )
                {
                    row.loader = v->fromSymbol;
                }
            }
        }
        if( row.loader != kNoNode )
        {
            row.rankClass = row.targetDef != kNoNode ? 1 : 3;
        }
    }
    std::ranges::stable_sort( rows, []( const Row& a, const Row& b )
    {
        return std::tie( a.rankClass, a.shownAt ) < std::tie( b.rankClass, b.shownAt );
    } );
    // the element
    std::vector<char> esc;
    std::string       x( kForDottedStringsLegend );
    const std::size_t shownRows = std::min( rows.size(), kForDottedStringRows );
    x += std::format( "<dotted_strings sites=\"{}\" rows=\"{}\"", rows.size(), shownRows );
    x += " hedge=\"a string in the source names this symbol; whether it flows to the import sink is not traced\"";   // on the element: --callers' legend layer keeps no comment
    if( testSites > 0 )
    {
        x += std::format( " tests=\"{}\"", testSites );
    }
    if( unresolvedN > 0 )
    {
        x += std::format( " unresolved=\"{}\"", unresolvedN );
    }
    if( externalN > 0 )
    {
        x += std::format( " external=\"{}\"", externalN );
    }
    if( rows.size() > shownRows )
    {
        x += " rows_capped=\"1\"";
        attr( x, "next", std::format( "--grep={}", rows[shownRows].site->recvVar ), esc );
    }
    else if( rows.empty() )
    {
        attr( x, "s", firstTestString, esc );
        attr( x, "next", std::format( "--grep={}", firstTestString ), esc );
    }
    x += '>';
    for( std::size_t k = 0; k < shownRows; ++k )
    {
        const Row&       row = rows[k];
        const Reference& r   = *row.site;
        x += "<ds";
        if( !row.candMod.empty() )
        {
            attr( x, "tmpl", r.recvVar, esc );
            attr( x, "cand", row.candMod, esc );
            x += std::format( " cands=\"{}\"", row.cands );
        }
        else
        {
            attr( x, "s", r.recvVar, esc );
            if( row.targetDef != kNoNode )
            {
                const Symbol& t = ing.symbols[ row.targetDef ];
                attr( x, "tn", displayName( t ), esc );
                attr( x, "tp", std::format( "{}:{}", rootRelPath( ing, t.fileId ), t.line ), esc );
            }
            else
            {
                attr( x, "mod", rootRelPath( ing, row.targetMod ), esc );
            }
        }
        attr( x, "p", rootRelPath( ing, r.fileId ), esc );
        x += std::format( " l=\"{}\"", r.line );
        if( const std::string in = siteInName( ing, r ); !in.empty() )
        {
            attr( x, "in", in, esc );
        }
        if( !r.memberPath.empty() )
        {
            attr( x, "sink", r.memberPath, esc );
        }
        if( row.loader != kNoNode )
        {
            const Symbol& l = ing.symbols[ row.loader ];
            attr( x, "loader", displayName( l ), esc );
            attr( x, "lp", std::format( "{}:{}", rootRelPath( ing, l.fileId ), l.line ), esc );
            if( row.loaders > 1 )
            {
                x += std::format( " loaders=\"{}\"", row.loaders );
            }
        }
        x += "/>";
    }
    x += "</dotted_strings>";
    return x;
}

}   // namespace rw
