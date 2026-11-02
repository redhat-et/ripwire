#pragma once

#include "model.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
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
// its declaration is written in (its Symbol::scope, the final segment the lookups key a class by). Views into the symbols,
// which outlive the graph build. Built once per graph (buildRubyGenerated); empty in a tree that declares none.
struct RubyGenerated
{
    struct Def
    {
        NodeId           id = kNoNode;
        RubyGenWhere     where = RubyGenWhere::Instance;
        std::string_view owner;
    };
    HashMap<std::string_view, std::vector<Def>> byName;
    mutable rw::SmallVec<NodeId, 2>             found;

    bool empty() const noexcept
    {
        return byName.empty();
    }

    // What `owner`'s declarations generate named `callee`, answering `where`; nullptr when nothing does. The list is reused:
    // read it before the next call.
    const rw::SmallVec<NodeId, 2>* in( std::string_view owner, std::string_view callee, RubyGenWhere where ) const
    {
        found.clear();
        if( const auto named = byName.find( callee ); named != byName.end() )
        {
            for( const Def& d : named->second )
            {
                if( d.where == where && d.owner == owner )
                {
                    found.push_back( d.id );
                }
            }
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

// Every generated method of `ing` (a scoped Ruby Section: a schema column is unscoped), each where its binding says it answers:
// a class method of the owner, of each includer (kRubyIncluderMark), or else an instance method.
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
    return out;
}

} // namespace rw
