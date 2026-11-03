#pragma once

#include "model.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// METHODS RUBY GENERATES (docs/research/ruby-roadmap.md R3; test/rubygeneratedcheck.sh; parser version 277).
//
// A class body's Rails DSL defines methods the source never spells as `def`: `has_many :bills` defines `bills` and
// `bills=`, `scope :active` a class method, `delegate :email, to: :owner` an instance method, an enum a predicate, a bang
// and two scopes per value. ingest_ruby.h captureRubyGeneratedDefs mints each as a Section definition of the class or
// concern around the declaration (its extent the token that names it), and captureRubyGeneratedSides marks a class method
// with a LocalBindKind::RubySingletonDef binding named for it. Such a definition is LOOKUP-ONLY (langfacts.h
// lookupOnlySections): it joins neither the name tier nor the `scope::name` index, and RubyGenerated below is the one place a
// lookup finds it — graph.h RubyClassObjects and RubyTypedReceivers, when no written method in the lookup answers. Rails keeps
// the association and attribute methods in modules it includes as the class inherits, before the body's own `include`s, so
// any written def in the class or a module it includes comes first.
//
// The table is data: which methods each declaration verb generates from the name it is given, read from Rails 8.1's
// ActiveRecord (associations/builder, enum.rb, scoping/named.rb, nested_attributes.rb), ActiveStorage (attached/model.rb) and
// ActiveSupport (core_ext/module/delegation.rb). Not minted (test/rubygeneratedcheck.sh floor (c)): a collection's
// `<singular>_ids` and an enum's pluralized class method, which need the inflector.

// Which side of the lookup a generated method answers on.
enum class RubyGenSide : std::uint8_t
{
    Instance,      // an instance method of the class (an association reader, a delegate, an enum predicate)
    ClassObject,   // a class method (a scope, an enum value's scope): a concern's is each includer's
};

// One method a declaration generates from a name `n` it is given: prefix + n + suffix, on `side`.
struct RubyGenName
{
    std::string_view prefix;
    std::string_view suffix;
    RubyGenSide      side;
};

// How a declaration's arguments name what it generates.
enum class RubyGenArgs : std::uint8_t
{
    First,       // its first argument, a symbol or plain string (`has_many :bills`, `scope :active`, `alias_method :new, :old`)
    Each,        // each symbol argument (`accepts_nested_attributes_for :a, :b`)
    Delegated,   // each symbol argument, renamed by `prefix:` (`delegate :a, to: :owner, prefix: true` defines owner_a)
    Enum,        // an enum's attribute (its reader and writer) and each value, renamed by `prefix:` / `suffix:`
};

// One declaration verb: what its arguments name, what it generates from each name, and where it may be written — Active
// Record's own (`modelOnly`) in a class body or a concern's `included do`; the rest in any class or module body too.
struct RubyGenVerb
{
    std::string_view             verb;
    RubyGenArgs                  args;
    bool                         modelOnly;
    std::span<const RubyGenName> names;
};

inline constexpr RubyGenSide kRubyGenI = RubyGenSide::Instance;
inline constexpr RubyGenSide kRubyGenC = RubyGenSide::ClassObject;

inline constexpr RubyGenName kRubyGenMethod[]       = { { "", "", kRubyGenI } };
inline constexpr RubyGenName kRubyGenReaderWriter[] = { { "", "", kRubyGenI }, { "", "=", kRubyGenI } };
inline constexpr RubyGenName kRubyGenSingular[]     = { { "", "", kRubyGenI }, { "", "=", kRubyGenI }, { "build_", "", kRubyGenI }, { "create_", "", kRubyGenI },
                                                        { "create_", "!", kRubyGenI }, { "reload_", "", kRubyGenI }, { "reset_", "", kRubyGenI } };
inline constexpr RubyGenName kRubyGenBelongsTo[]    = { { "", "", kRubyGenI }, { "", "=", kRubyGenI }, { "build_", "", kRubyGenI }, { "create_", "", kRubyGenI },
                                                        { "create_", "!", kRubyGenI }, { "reload_", "", kRubyGenI }, { "reset_", "", kRubyGenI },
                                                        { "", "_changed?", kRubyGenI }, { "", "_previously_changed?", kRubyGenI } };
inline constexpr RubyGenName kRubyGenScope[]        = { { "", "", kRubyGenC } };
inline constexpr RubyGenName kRubyGenAttachedOne[]  = { { "", "", kRubyGenI }, { "", "=", kRubyGenI }, { "", "_attachment", kRubyGenI }, { "", "_blob", kRubyGenI },
                                                        { "with_attached_", "", kRubyGenC } };
inline constexpr RubyGenName kRubyGenAttachedMany[] = { { "", "", kRubyGenI }, { "", "=", kRubyGenI }, { "", "_attachments", kRubyGenI }, { "", "_blobs", kRubyGenI },
                                                        { "with_attached_", "", kRubyGenC } };
inline constexpr RubyGenName kRubyGenNested[]       = { { "", "_attributes=", kRubyGenI } };
inline constexpr RubyGenName kRubyGenEnumValue[]    = { { "", "?", kRubyGenI }, { "", "!", kRubyGenI }, { "", "", kRubyGenC }, { "not_", "", kRubyGenC } };

// In verb order, for reading: ingest_ruby.h finds a verb's row with rw::findByField (twelve rows).
inline constexpr RubyGenVerb kRubyGeneratedVerbs[] = {
    { "accepts_nested_attributes_for", RubyGenArgs::Each, true, kRubyGenNested },
    { "alias_method", RubyGenArgs::First, false, kRubyGenMethod },
    { "belongs_to", RubyGenArgs::First, true, kRubyGenBelongsTo },
    { "define_method", RubyGenArgs::First, false, kRubyGenMethod },
    { "delegate", RubyGenArgs::Delegated, false, kRubyGenMethod },
    { "enum", RubyGenArgs::Enum, true, kRubyGenEnumValue },
    { "has_and_belongs_to_many", RubyGenArgs::First, true, kRubyGenReaderWriter },
    { "has_many", RubyGenArgs::First, true, kRubyGenReaderWriter },
    { "has_many_attached", RubyGenArgs::First, true, kRubyGenAttachedMany },
    { "has_one", RubyGenArgs::First, true, kRubyGenSingular },
    { "has_one_attached", RubyGenArgs::First, true, kRubyGenAttachedOne },
    { "scope", RubyGenArgs::First, true, kRubyGenScope },
};

// An enum's options (ActiveRecord::Enum: the Rails 7 spelling and the older underscored one), never one of its attributes or
// values.
inline constexpr std::string_view kRubyEnumOptions[] = { "_default", "_instance_methods", "_prefix", "_scopes", "_suffix", "default", "instance_methods",
                                                         "prefix", "scopes", "suffix", "validate" };


// Where a generated method answers: an instance's lookup, the owner's class object, or the class object of each class
// including the owner (a concern's `included do`).
enum class RubyGenWhere : std::uint8_t
{
    Instance,
    ClassObject,
    Includers,
};

// Every generated method of a Ruby tree (the note above), by name: its definition, where it answers, and the class or module
// its declaration is written in (its Symbol::scope, the final segment the lookups key a class by). A schema column (the note
// below) is its model's: owner the model's name, `model` its class. Views into the symbols, which outlive the graph build.
// Built once per graph (buildRubyGenerated); empty in a tree that declares none.
struct RubyGenerated
{
    struct Def
    {
        NodeId           id = kNoNode;
        RubyGenWhere     where = RubyGenWhere::Instance;
        std::string_view owner;
        NodeId           model = kNoNode;   // a column's model class; kNoNode for a declaration's method, whose class is around it
    };
    HashMap<std::string_view, std::vector<Def>> byName;
    mutable rw::SmallVec<NodeId, 2>             found;
    mutable rw::SmallVec<NodeId, 2>             foundModels;   // each found definition's Def::model, index for index

    bool empty() const noexcept
    {
        return byName.empty();
    }

    // What `owner`'s declarations generate named `callee`, answering `where`, each definition once; nullptr when nothing does.
    // The lists are reused: read them before the next call.
    const rw::SmallVec<NodeId, 2>* in( std::string_view owner, std::string_view callee, RubyGenWhere where ) const
    {
        found.clear();
        foundModels.clear();
        if( const auto named = byName.find( callee ); named != byName.end() )
        {
            for( const Def& d : named->second )
            {
                if( d.where == where && d.owner == owner && std::ranges::find( found, d.id ) == found.end() )
                {
                    found.push_back( d.id );
                    foundModels.push_back( d.model );
                }
            }
        }
        return found.empty() ? nullptr : &found;
    }

    // `found` without its schema columns when they are of more than one model — a name several models share (two classes
    // named `Base`, each with its table) shows the receiver to be none of them; nullptr when nothing is left.
    const rw::SmallVec<NodeId, 2>* ofOneModel() const
    {
        NodeId first = kNoNode;
        bool   many  = false;
        for( const NodeId m : foundModels )
        {
            many  = many || ( m != kNoNode && first != kNoNode && m != first );
            first = first == kNoNode ? m : first;
        }
        std::size_t kept = 0;   // the declarations' methods, in order
        for( std::size_t k = 0; many && k < found.size(); ++k )
        {
            if( foundModels[ k ] == kNoNode )
            {
                found[ kept++ ] = found[ k ];
            }
        }
        if( many )
        {
            found.resize( kept );
            foundModels.assign( kept, kNoNode );
        }
        return found.empty() ? nullptr : &found;
    }
};

// The key that joins a class-method binding (LocalBindKind::RubySingletonDef, var = the generated name) to its definition:
// one token can name methods of both sides (an enum value's `trial?` and its `trial` scope), so the name is part of it.
inline std::string rubyGeneratedSiteKey( std::uint32_t fileId, std::uint32_t startByte, std::string_view name )
{
    std::string k = std::to_string( fileId );
    k.append( 1, ':' ).append( std::to_string( startByte ) ).append( 1, '#' ).append( name );
    return k;
}

// ── A schema column as a reader of its model (parser version 279, test/rubycolumncheck.sh) ──────────────────────────────────
// A rendered db/schema.rb column (ingest_ruby.h's schema capture: an unscoped Ruby Section inside a create_table's bytes) is
// the attribute reader every instance of its table's model answers, and it answers like a declaration's method: last in the
// lookup, and after a declaration's method of its name (an enum's `status` before the `status` column). A model's table is
// the name its class body gives `self.table_name =`; else, for a class written `< ApplicationRecord`, its name underscored and
// pluralized by the regular English rules below. Not ported: Rails' irregular, uncountable and other
// special plurals (a class they name reads no table). Refused: a class under a module defining `table_name_prefix`, or nested
// in a model, whose table Rails prefixes, and a class written directly `< ActiveRecord::Base` (rubyModelRootBase). An STI
// subclass reads its base class's table through the lookup's ancestor walk, so only a class written directly below
// ApplicationRecord reads a table by its name. The tables and table names are
// LocalBindKind::RubyTable bindings (ingest_ruby.h captureRubyTables).

// `ParcelTag` → `parcel_tag`, `HTMLPage` → `html_page`: ActiveSupport's underscore of a class's final segment
inline std::string rubyUnderscore( std::string_view cls )
{
    const auto upper = []( char c ) noexcept { return c >= 'A' && c <= 'Z'; };
    const auto lower = []( char c ) noexcept { return ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ); };
    std::string out;
    for( std::size_t i = 0; i < cls.size(); ++i )
    {
        const char c = cls[ i ];
        if( i > 0 && upper( c ) && ( lower( cls[ i - 1 ] ) || ( upper( cls[ i - 1 ] ) && i + 1 < cls.size() && lower( cls[ i + 1 ] ) ) ) )
        {
            out.push_back( '_' );
        }
        out.push_back( upper( c ) ? char( c - 'A' + 'a' ) : c );
    }
    return out;
}

// A model's default table: `ParcelTag` → `parcel_tags`, `Category` → `categories`, `Box` → `boxes` — the class's underscored
// name, then +es after s, x, z, ch or sh, a consonant's y to ies, else +s
inline std::string rubyDefaultTableName( std::string_view cls )
{
    std::string            out = rubyUnderscore( cls );
    const std::string_view w( out );
    if( w.ends_with( 's' ) || w.ends_with( 'x' ) || w.ends_with( 'z' ) || w.ends_with( "ch" ) || w.ends_with( "sh" ) )
    {
        return out.append( "es" );
    }
    if( w.size() > 1 && w.ends_with( 'y' ) && std::string_view( "aeiou" ).find( w[ w.size() - 2 ] ) == std::string_view::npos )
    {
        out.pop_back();
        return out.append( "ies" );
    }
    return out.append( "s" );
}

// Is `r` a class's superclass reference to ApplicationRecord, the root a model is written below? (A Ruby inherit reference
// keeps only the final segment, so `< ActiveRecord::Base` is a `Base` like any other: not read, test/rubycolumncheck.sh (e).)
inline bool rubyModelRootBase( const IngestResult& ing, const Reference& r ) noexcept
{
    return r.isInherit && r.lang == Lang::Ruby && r.calleeName == "ApplicationRecord" && r.fromSymbol < ing.symbols.size()
        && ing.symbols[ r.fromSymbol ].kind == SymKind::Class;
}

// The innermost of `classes` (one file's, in byte order) holding `byte`; kNoNode when none does.
inline NodeId rubyInnermostClassAt( const IngestResult& ing, std::span<const NodeId> classes, std::uint32_t byte ) noexcept
{
    NodeId inner = kNoNode;
    for( const NodeId c : classes )
    {
        inner = ing.symbols[ c ].sigStartByte <= byte && byte < ing.symbols[ c ].endByte ? c : inner;   // the last holder is innermost
    }
    return inner;
}

// Each class whose body names its table (`self.table_name =`, a RubyTable binding marked kRubyModelTableMark), with the name:
// the innermost class of the binding's file holding its byte.
inline HashMap<NodeId, std::string> rubyNamedTables( const IngestResult& ing )
{
    HashMap<std::uint32_t, std::vector<NodeId>> classesByFile;   // Ruby classes, in symbol (file, byte) order
    for( const Symbol& s : ing.symbols )
    {
        if( s.lang == Lang::Ruby && s.kind == SymKind::Class )
        {
            classesByFile[ s.fileId ].push_back( s.id );
        }
    }
    HashMap<NodeId, std::string> out;
    for( const Binding& b : ing.bindings )
    {
        const auto   file  = b.kind == LocalBindKind::RubyTable && b.importedName == kRubyModelTableMark ? classesByFile.find( b.fileId ) : classesByFile.end();
        const NodeId inner = file != classesByFile.end() ? rubyInnermostClassAt( ing, file->second, b.startByte ) : kNoNode;
        if( inner != kNoNode )
        {
            out.insert_or_assign( inner, b.var );
        }
    }
    return out;
}

// The modules defining `table_name_prefix`, by final segment
inline HashMap<std::string_view, char> rubyTablePrefixModules( const IngestResult& ing )
{
    HashMap<std::string_view, char> out;
    for( const Symbol& s : ing.symbols )
    {
        if( s.lang == Lang::Ruby && s.name == "table_name_prefix" && !s.scope.empty() )
        {
            const std::size_t cut = s.scope.rfind( "::" );
            out.try_emplace( std::string_view( s.scope ).substr( cut == std::string::npos ? 0 : cut + 2 ), 1 );
        }
    }
    return out;
}

// Does Rails prefix the table of a class in `scope`: a module around it defines `table_name_prefix`, or it is nested in a
// model (each by final segment)?
inline bool rubyTablePrefixed( std::string_view scope, const HashMap<std::string_view, char>& prefixModules, const HashMap<std::string_view, char>& models )
{
    for( std::size_t at = 0; at < scope.size(); )
    {
        const std::size_t      cut  = scope.find( "::", at );
        const bool             last = cut == std::string_view::npos;
        const std::string_view seg  = scope.substr( at, last ? std::string_view::npos : cut - at );
        if( prefixModules.find( seg ) != prefixModules.end() || ( last && models.find( seg ) != models.end() ) )
        {
            return true;
        }
        at = last ? scope.size() : cut + 2;
    }
    return false;
}

// Each model class of `ing` with the table it reads (the note above), in class order.
inline std::vector<std::pair<NodeId, std::string>> rubyModelTables( const IngestResult& ing )
{
    const HashMap<NodeId, std::string> named = rubyNamedTables( ing );
    HashMap<NodeId, char>              byName;   // classes written below ApplicationRecord that name no table
    HashMap<std::string_view, char>    models;   // every model's name, for the nested-in-a-model refusal
    for( const auto& [ c, t ] : named )
    {
        models.try_emplace( ing.symbols[ c ].name, 1 );
    }
    for( const Reference& r : ing.references )
    {
        if( rubyModelRootBase( ing, r ) && named.find( r.fromSymbol ) == named.end() )
        {
            byName.try_emplace( r.fromSymbol, 1 );
            models.try_emplace( ing.symbols[ r.fromSymbol ].name, 1 );
        }
    }
    const HashMap<std::string_view, char>       prefixModules = rubyTablePrefixModules( ing );
    std::vector<std::pair<NodeId, std::string>> out;
    for( const Symbol& s : ing.symbols )
    {
        if( const auto table = named.find( s.id ); table != named.end() )
        {
            out.emplace_back( s.id, table->second );
        }
        else if( byName.find( s.id ) != byName.end() && !rubyTablePrefixed( s.scope, prefixModules, models ) )
        {
            out.emplace_back( s.id, rubyDefaultTableName( s.name ) );
        }
    }
    return out;
}

// Each column of `ing`'s rendered schemas, by its table's name: an unscoped Ruby Section inside a create_table's bytes.
inline HashMap<std::string_view, std::vector<NodeId>> rubyTableColumns( const IngestResult& ing )
{
    struct Span
    {
        std::uint32_t    start = 0;
        std::uint32_t    end   = 0;
        std::string_view name;
    };
    HashMap<std::uint32_t, std::vector<Span>> spans;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind == LocalBindKind::RubyTable && b.importedName.empty() && b.spanEnd > b.spanStart )
        {
            spans[ b.fileId ].push_back( { b.spanStart, b.spanEnd, b.var } );
        }
    }
    HashMap<std::string_view, std::vector<NodeId>> out;
    for( const Symbol& s : ing.symbols )
    {
        const auto file = s.lang == Lang::Ruby && s.kind == SymKind::Section && s.scope.empty() ? spans.find( s.fileId ) : spans.end();
        for( const Span& t : file != spans.end() ? std::span<const Span>( file->second ) : std::span<const Span> {} )
        {
            if( t.start <= s.sigStartByte && s.sigStartByte < t.end )
            {
                out[ t.name ].push_back( s.id );
                break;
            }
        }
    }
    return out;
}

// Each column a model reads (the note above): (model class, column), in class then column order.
inline std::vector<std::pair<NodeId, NodeId>> rubyColumnReads( const IngestResult& ing )
{
    std::vector<std::pair<NodeId, NodeId>>               out;
    const HashMap<std::string_view, std::vector<NodeId>> columns = rubyTableColumns( ing );
    if( columns.empty() )
    {
        return out;
    }
    for( const auto& [ model, tableName ] : rubyModelTables( ing ) )
    {
        const auto table = columns.find( tableName );
        for( const NodeId c : table != columns.end() ? std::span<const NodeId>( table->second ) : std::span<const NodeId> {} )
        {
            out.emplace_back( model, c );
        }
    }
    return out;
}

// Each column's models, by name, into `out`: the classes whose lookups own it (graph.h RubySelfReach::modelsOf).
inline void rubyColumnModels( const IngestResult& ing, HashMap<NodeId, std::vector<std::string>>& out )
{
    for( const auto& [ model, c ] : rubyColumnReads( ing ) )
    {
        out[ c ].push_back( ing.symbols[ model ].name );
    }
}

// Each model's columns into `out`, as instance readers of the model — after a declaration's method of the column's name.
inline void addRubyColumns( const IngestResult& ing, RubyGenerated& out )
{
    for( const auto& [ model, c ] : rubyColumnReads( ing ) )
    {
        const std::string_view           owner = ing.symbols[ model ].name;
        std::vector<RubyGenerated::Def>& named = out.byName[ ing.symbols[ c ].name ];
        const bool taken = std::ranges::any_of( named, [ & ]( const RubyGenerated::Def& d )
        { return d.owner == owner && d.where == RubyGenWhere::Instance && ( d.model == kNoNode || d.id == c ); } );
        if( !taken )
        {
            named.push_back( { c, RubyGenWhere::Instance, owner, model } );
        }
    }
}

// Every generated method of `ing` (a scoped Ruby Section: a schema column is unscoped), each where its binding says it answers:
// a class method of the owner, of each includer (kRubyIncluderMark), or else an instance method; then each model's columns.
inline RubyGenerated buildRubyGenerated( const IngestResult& ing )
{
    HashMap<std::string, RubyGenWhere> classSites;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind == LocalBindKind::RubySingletonDef && b.typeName.empty() && !b.var.empty() )
        {
            const RubyGenWhere where = b.importedName == kRubyIncluderMark ? RubyGenWhere::Includers : RubyGenWhere::ClassObject;
            classSites.try_emplace( rubyGeneratedSiteKey( b.fileId, b.startByte, b.var ), where );
        }
    }
    RubyGenerated out;
    for( const Symbol& s : ing.symbols )
    {
        if( s.lang == Lang::Ruby && s.kind == SymKind::Section && !s.scope.empty() )
        {
            const auto site = classSites.find( rubyGeneratedSiteKey( s.fileId, s.sigStartByte, s.name ) );
            out.byName[ s.name ].push_back( { s.id, site != classSites.end() ? site->second : RubyGenWhere::Instance, s.scope } );
        }
    }
    addRubyColumns( ing, out );
    return out;
}

} // namespace rw
