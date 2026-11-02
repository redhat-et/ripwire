#pragma once

// restlinks.h — the two reST links no path spells, for graph.h's bindMarkdownLinks. ingest_rest.h writes them on
// RawRef::memberPath behind a mark a markdown link cannot start with (infra/mdslug.h). Everything else, a relative
// :doc: included, is an ordinary written path. Gate: test/restdocscheck.sh.

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "infra/mdslug.h"
#include "infra/sortutil.h"
#include "langfacts.h"
#include "model.h"
#include "resolve.h"

namespace rw
{

struct RestLinkIndex
{
    std::vector<std::pair<std::string_view, NodeId>> labels;       // `_name` Sections, sorted (name, id): the lowest id of a name is its target
    std::vector<std::string>                         sphinxRoots;  // directories holding a conf.py, sorted, normalized
};

// Empty unless a reference asks. Names point into ing.symbols, which outlives the index.
inline RestLinkIndex buildRestLinkIndex( const IngestResult& ing )
{
    RestLinkIndex rx;
    const bool    wantsLabel = std::any_of( ing.references.begin(), ing.references.end(), []( const Reference& r ) { return r.memberPath.starts_with( kRestLabelMark ); } );
    const bool    wantsRoot  = std::any_of( ing.references.begin(), ing.references.end(), []( const Reference& r ) { return r.memberPath.starts_with( kRestDocRootMark ); } );
    if( wantsLabel )
    {
        for( const Symbol& sym : ing.symbols )
        {
            if( sym.kind == SymKind::Section && sym.name.starts_with( '_' ) && langFacts( sym.lang ).linkSections )
            {
                rx.labels.emplace_back( sym.name, sym.id );
            }
        }
        std::sort( rx.labels.begin(), rx.labels.end(), []( const auto& a, const auto& b )
        {
            return rw::sortutil::svLess( a.first, b.first ) || ( a.first == b.first && a.second < b.second );
        } );
    }
    if( wantsRoot )
    {
        for( const std::string& file : ing.files )
        {
            if( file == "conf.py" || file.ends_with( "/conf.py" ) )
            {
                rx.sphinxRoots.push_back( lexicalNormalize( includerDir( file ) ) );
            }
        }
        std::sort( rx.sphinxRoots.begin(), rx.sphinxRoots.end() );
    }
    return rx;
}

inline NodeId bindRestLabel( const RestLinkIndex& rx, std::string_view label )
{
    std::string name( 1, '_' );
    name.append( label );
    const auto byName = []( const std::pair<std::string_view, NodeId>& row, std::string_view key ) { return rw::sortutil::svLess( row.first, key ); };
    const auto hit    = std::lower_bound( rx.labels.begin(), rx.labels.end(), name, byName );   // byName is svLess on the name
    return hit != rx.labels.end() && hit->first == name ? hit->second : kNoNode;
}

// :doc:`/a/b` is relative to the Sphinx root: the nearest ancestor of the linker holding a conf.py. A linker under none, or a
// path not in the tree, leaves the stem ladder to answer, as for any link whose file is not in the tree.
template<class FileMap>
inline NodeId bindRestRootDoc( const RestLinkIndex& rx, const FileMap& fileByPath, const std::vector<NodeId>& wholeFile, std::string_view linkerPath, std::string_view written )
{
    std::string dir = lexicalNormalize( includerDir( linkerPath ) );
    for( ;; )
    {
        if( std::binary_search( rx.sphinxRoots.begin(), rx.sphinxRoots.end(), dir ) )
        {
            const std::string path = lexicalNormalize( dir.empty() ? std::string( written ) : dir + "/" + std::string( written ) );
            const auto        hit  = path.empty() ? fileByPath.end() : fileByPath.find( path );
            return hit == fileByPath.end() ? kNoNode : wholeFile[ hit->second ];
        }
        if( dir.empty() )
        {
            return kNoNode;
        }
        const std::size_t slash = dir.find_last_of( '/' );
        dir.resize( slash == std::string::npos ? 0 : slash );
    }
}

// True when `written` is one of the two marked links, with `pin` set; kNoNode then drops a label and lets a :doc: stem ladder answer.
template<class FileMap>
inline bool bindRestLink( const RestLinkIndex& rx, const FileMap& fileByPath, const std::vector<NodeId>& wholeFile, std::string_view linkerPath, std::string_view written, NodeId& pin )
{
    if( written.starts_with( kRestLabelMark ) )
    {
        pin = bindRestLabel( rx, written.substr( kRestLabelMark.size() ) );
        return true;
    }
    if( written.starts_with( kRestDocRootMark ) )
    {
        pin = bindRestRootDoc( rx, fileByPath, wholeFile, linkerPath, written.substr( kRestDocRootMark.size() ) );
        return true;
    }
    return false;
}

} // namespace rw
