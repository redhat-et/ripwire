#pragma once

#include "externalnames.h"
#include "model.h"

#include <algorithm>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// THE RAILS FRAMEWORK ROWS of the builtin-method gate (test/rubyframeworknamescheck.sh; graph.h BuiltinMethodGate, which
// reads the tables this returns beside the language's builtin table; the names and their generator commands are in
// externalnames.h). A framework's table joins when the tree USES the framework and does not DEFINE it:
//   * uses: a constant the tree writes as a superclass, a mixin, a receiver, an argument or a rescued class
//     (Include::isSymbolic, the constant as written) has one of the row's namespaces as its first segment —
//     `< ActiveRecord::Base`, `extend ActiveSupport::Concern`, `Rails.logger`, `rescue ActiveRecord::RecordNotFound`;
//   * defines: the tree opens the row's home constant. The Rails gems' own trees open it (lib/active_record/relation/
//     query_methods.rb opens ActiveRecord::QueryMethods), and their methods are in-tree definitions the gate has no reason
//     to doubt, so those trees keep their maps.
// Ruby-only: the evidence is Ruby's constant spelling and Ruby's constant index (resolve.h RubyBaseScope::opened, empty in a
// tree with no Ruby superclass or mixin — the home test then finds nothing and only the uses test decides).
struct RubyFrameworkRow
{
    std::string_view        home;         // a constant whose open shows the tree defines the framework: the row stays off
    const std::string_view* uses;         // the namespaces whose constants show the tree uses it (sorted)
    std::size_t             usesCount;
    const std::string_view* names;        // the framework's method names (sorted)
    std::size_t             namesCount;
};
inline constexpr RubyFrameworkRow kRubyFrameworkRows[] = {
    { "ActiveSupport::Concern", externalnames::kRailsNamespaces, std::size( externalnames::kRailsNamespaces ),
      externalnames::kRubyActiveSupportMethodNames, std::size( externalnames::kRubyActiveSupportMethodNames ) },
    { "ActiveRecord::QueryMethods", externalnames::kActiveRecordNamespaces, std::size( externalnames::kActiveRecordNamespaces ),
      externalnames::kRubyActiveRecordMethodNames, std::size( externalnames::kRubyActiveRecordMethodNames ) },
};

// Does the constant as written (`::ActiveRecord::Base`, `Rails`) start with one of `namespaces` as its first segment?
inline bool rubyConstantUnder( std::string_view written, std::span<const std::string_view> namespaces ) noexcept
{
    written                     = written.starts_with( "::" ) ? written.substr( 2 ) : written;
    const std::string_view head = written.substr( 0, written.find( "::" ) );
    return std::binary_search( namespaces.begin(), namespaces.end(), head );
}

// The tables of the rows whose framework the tree uses and does not define, in row order. `opened` is the constant of every
// Ruby class or module open in the tree (RubyBaseScope::opened).
inline std::vector<std::span<const std::string_view>> rubyFrameworkTablesInUse( const IngestResult& ing, const HashMap<std::string, char>& opened )
{
    std::vector<std::span<const std::string_view>> out;
    for( const RubyFrameworkRow& row : kRubyFrameworkRows )
    {
        const std::span<const std::string_view> uses( row.uses, row.usesCount );
        const bool used    = std::ranges::any_of( ing.includes, [ & ]( const Include& inc ) { return inc.isSymbolic && rubyConstantUnder( inc.target, uses ); } );
        const bool defined = opened.find( std::string( row.home ) ) != opened.end();
        if( used && !defined )
        {
            out.emplace_back( row.names, row.namesCount );
        }
    }
    return out;
}

} // namespace rw
