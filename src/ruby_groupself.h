#pragma once

#include "model.h"

#include <algorithm>
#include <charconv>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// THE SELF OF AN RSPEC EXAMPLE GROUP (test/rubygroupselfcheck.sh; parser version 273 records it — model.h
// LocalBindKind::RubyGroupSelf / RubyGroupMixin, written by ingest_ruby.h captureRubyExampleGroups).
//
// Inside `RSpec.describe … do` the block is evaluated on a new example-group class, and `it`, `let` and `before` blocks
// run on an instance of it, so a receiver-less call there is sent to the group (or its example) and Ruby answers it from
// that object's lookup: the defs written in the group and its parents, the modules the groups mix in (`config.include M`,
// `include M` in a group), RSpec's own modules, then Object, where a top-level def lives. RSpec, FactoryBot and Capybara
// are outside the tree; an application class's method is in no example's lookup at all. graph.h RubyTopSelf asks this
// index two questions — is a call inside a group, and does a module the groups mix in own a candidate — and decides the
// rest beside main's and a view's self. Ruby-only (see captureRubyExampleGroups).
struct RubyGroupSelf
{
    using Span = std::pair<std::uint32_t, std::uint32_t>;   // [start, end) bytes of a block
    std::vector<std::vector<Span>> groups;                  // per file: the outermost group blocks, sorted, disjoint
    std::vector<std::vector<Span>> shared;                  // per file: the same for a shared group and a configure block
    std::vector<std::vector<Span>> holes;                   // per file: blocks inside them whose self is another object's
    std::vector<std::string>       mixins;                  // the modules the groups take in and their ancestors, sorted,
                                                            // each also by its final segment (an owner may be either)

    // The last span of `spans` that starts at or before `byte` contains it? (sorted and disjoint: one probe)
    static bool inside( const std::vector<Span>& spans, std::uint32_t byte ) noexcept
    {
        const auto after = std::upper_bound( spans.begin(), spans.end(), byte, []( std::uint32_t b, const Span& s ) { return b < s.first; } );
        return after != spans.begin() && byte < std::prev( after )->second;
    }

    // Is the byte at `byte` of file `fileId` in a group's block, and in no block inside it that hands self elsewhere?
    bool contains( std::uint32_t fileId, std::uint32_t byte ) const noexcept
    {
        return fileId < groups.size() && ( inside( groups[ fileId ], byte ) || inside( shared[ fileId ], byte ) ) && !inside( holes[ fileId ], byte );
    }

    // Is a def starting at `byte` of file `fileId` written inside a group that is not shared? Then it is that group's
    // method, which no other file's group reaches: the defs a group's lookup reaches with no class around them are its own
    // file's, a shared group's (`include_context` brings them in) and the true top-level ones (a spec/support helper).
    bool groupDef( std::uint32_t fileId, std::uint32_t byte ) const noexcept
    {
        return fileId < groups.size() && inside( groups[ fileId ], byte );
    }

    // Is candidate `s` out of every lookup a group in file `callerFile` makes, whoever owns it? A definition in another
    // language (an application's JavaScript `create`), and a def written inside ANOTHER file's unshared group.
    bool outOfReach( const Symbol& s, std::uint32_t callerFile ) const noexcept
    {
        return s.lang != Lang::Ruby || ( s.scope.empty() && s.fileId != callerFile && groupDef( s.fileId, s.sigStartByte ) );
    }

    // Does a module the groups mix in own a candidate whose owner is `owner`?
    bool mixes( std::string_view owner ) const noexcept
    {
        const auto has = [ & ]( std::string_view n ) { return std::binary_search( mixins.begin(), mixins.end(), n ); };
        const std::size_t cut = owner.rfind( "::" );
        return !owner.empty() && ( has( owner ) || ( cut != std::string_view::npos && has( owner.substr( cut + 2 ) ) ) );
    }

    // A group's self, as the key graph.h's Ruby lookups carry it: "<group>N" for file N, so the lookup knows its own file.
    static constexpr std::string_view kKey = "<group>";
    static bool isKey( std::string_view self ) noexcept { return self.starts_with( kKey ); }
    static std::uint32_t fileOf( std::string_view self ) noexcept
    {
        std::uint32_t file = 0;
        std::from_chars( self.data() + kKey.size(), self.data() + self.size(), file );
        return file;
    }

    // Building: one span record, one mixin name (and its final segment), then sorting and the per-file keys.
    void noteSpan( const Binding& b );
    void noteMixin( const std::string& name );
    void finish();
    std::vector<std::string> keys;   // per file: its groups' self key (empty for a file with none)
};

// RubyGroupSelf's builders, in the order buildRubyGroupSelf calls them.
inline void RubyGroupSelf::noteSpan( const Binding& b )
{
    auto& into = b.importedName == kRubyGroupHoleMark ? holes : b.importedName == kRubyGroupSharedMark ? shared : groups;
    into[ b.fileId ].emplace_back( b.spanStart, b.spanEnd );
}

inline void RubyGroupSelf::noteMixin( const std::string& name )
{
    mixins.push_back( name );
    if( const std::size_t cut = name.rfind( "::" ); cut != std::string::npos )
    {
        mixins.push_back( name.substr( cut + 2 ) );
    }
}

inline void RubyGroupSelf::finish()
{
    for( auto* perFile : { &groups, &shared, &holes } )
    {
        for( std::vector<Span>& spans : *perFile )
        {
            std::sort( spans.begin(), spans.end() );
        }
    }
    std::sort( mixins.begin(), mixins.end() );
    mixins.erase( std::unique( mixins.begin(), mixins.end() ), mixins.end() );
    keys.resize( groups.size() );
    for( std::uint32_t f = 0; f < groups.size(); ++f )
    {
        keys[ f ] = groups[ f ].empty() && shared[ f ].empty() ? std::string {} : std::string( kKey ) + std::to_string( f );
    }
}

// Does `path` sit under a directory `dir` (written with its trailing slash) — its last `dir`, at the start or after a `/`?
inline bool rubyPathUnder( std::string_view path, std::string_view dir ) noexcept
{
    const std::size_t at = path.rfind( dir );
    return at != std::string_view::npos && ( at == 0 || path[ at - 1 ] == '/' );
}

// Does a group's mixin record count? A described constant (kRubyGroupDescribedMark) only in a helper spec by rspec-rails'
// location rule (infer_spec_type_from_file_location!: a file under spec/helpers/); every other record always.
inline bool rubyGroupMixinKept( const IngestResult& ing, const Binding& b ) noexcept
{
    return !b.typeName.empty() && ( b.importedName != kRubyGroupDescribedMark || ( b.fileId < ing.files.size() && rubyPathUnder( ing.files[ b.fileId ], "spec/helpers/" ) ) );
}

// RubyGroupSelf over one ingest. `ancestorsOf( name )` lists a module and every name above it (graph.h RubySelfReach's,
// over the Ruby inheritance graph with mixins), so a module the groups include brings its own mixins along.
template<class Ancestors>
inline RubyGroupSelf buildRubyGroupSelf( const IngestResult& ing, const Ancestors& ancestorsOf )
{
    RubyGroupSelf out;
    out.groups.resize( ing.files.size() );
    out.shared.resize( ing.files.size() );
    out.holes.resize( ing.files.size() );
    for( const Binding& b : ing.bindings )
    {
        if( b.kind == LocalBindKind::RubyGroupSelf && b.fileId < ing.files.size() )
        {
            out.noteSpan( b );
        }
        else if( b.kind == LocalBindKind::RubyGroupMixin && rubyGroupMixinKept( ing, b ) )
        {
            out.noteMixin( b.typeName );
            const std::size_t cut = b.typeName.rfind( "::" );
            for( const std::string& a : ancestorsOf( cut == std::string::npos ? b.typeName : b.typeName.substr( cut + 2 ) ) )
            {
                out.noteMixin( a );
            }
        }
    }
    out.finish();
    return out;
}

} // namespace rw
