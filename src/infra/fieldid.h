#pragma once
// fieldid.h — read a tree-sitter node's FIELD child without re-deriving the field's id from its name.
//
// WHY THIS EXISTS. `ts_node_child_by_field_name( n, "name", 4 )` — 199 call sites across the ingest
// walk sections, `--slice` and the preprocessor reader — does not look a field up. It looks the field's
// NAME up first, every time, and the lookup it runs is a linear `strncmp` scan over the grammar's whole
// field table (third_party/deps/tree_sitter/lib/src/language.c, `ts_language_field_id_for_name`):
//
//     for( TSSymbol i = 1; i < count + 1; i++ ) { switch( strncmp( name, self->field_names[i], name_length ) ) { … } }
//
// The answer is a pure function of ( grammar, field name ) and never changes for the life of the
// process, so this is loop-invariant work recomputed per AST NODE. It is also F3's defect one layer
// down: `strncmp` is an EXTERNAL libc symbol, so LTO cannot reach it, and on macOS every one of those
// comparisons is a call through TWO dyld stubs — `DYLD-STUB$$strncmp` in our image, then
// `DYLD-STUB$$_platform_strncmp` in libsystem_platform — before `_platform_strncmp` starts.
//
// MEASURED, on the audit tree at 9356cf23 (docs/OPTREMARKS.md §8b/F3 is the same shape one layer up).
// A 1 ms `sample` of a cold `--no-cache` run over the go corpus (15,865 files), 18,963 busy leaf
// samples: `strncmp` + its two dyld stubs are **3.44 %** of busy CPU, the `ts_node_child_by_field_name`
// subtree is 4.70 %, and **93.6 % of that subtree is owned by one caller** — `cc_boolOp`, which
// `cc_walk` asks twice per AST node at the fall-through of its dispatch. The host tree's own share
// is 2.56 % (it is markdown-heavy, so less of it is AST walk).
//
// WHAT IT REPLACES IT WITH. `fieldChild( n, NodeField::Name )` resolves the id ONCE PER GRAMMAR, at
// the ingest prewarm (`warmFieldIdTable()` in ingest_crawl.h, which owns the grammar table), into a
// [grammar][field] table of `TSFieldId`, and then calls `ts_node_child_by_field_id` directly. Three
// properties matter:
//
//   • It is the SAME CALL the by-name form makes. `ts_node_child_by_field_name` is literally
//     `ts_node_child_by_field_id( self, ts_language_field_id_for_name( self.tree->language, name, len ) )`
//     (node.c:773). Removing the middle term cannot change the node returned — it removes a pure
//     function's recomputation, not a decision.
//   • A grammar that HAS NO SUCH FIELD keeps the by-name answer exactly. `ts_language_field_id_for_name`
//     returns 0 for an unknown name, and `ts_node_child_by_field_id( n, 0 )` returns the null node on
//     its first line (`if (!field_id || …) return ts_node__null();`, node.c:602). So a 0 in this table
//     is not a hole to guard against — it IS the "this grammar has no `receiver:`" answer, and the
//     single-language arms that rely on it (ingest_relations.h's Go/Ruby split, for one) keep working
//     unchanged. test/fieldidcheck.sh arm C proves the parity rather than asserting it.
//   • An UNWARMED grammar is correct, not broken. The lookup falls back to resolving by name — today's
//     code path, today's answer, today's cost. Nothing here can return a wrong node because a warm was
//     missed; it can only fail to be faster, which is what arm E of the gate is for.
//
// THREADING. The registry is written ONLY by `warmFieldIds`, and only from the single-threaded prewarm
// before any parse worker exists — the same invariant, and the same reason, as `compiledQueryCache()`
// in ingest_crawl.h: workers then only READ it, so no lock is on the per-node path. `warmFieldIds` is
// idempotent (a second warm of the same grammar is a no-op), so a caller does not have to know whether
// it ran. Do NOT call it from a worker thread.
//
// SCOPE. Every `ts_node_child_by_field_name` site in src/ is on this, per-node path or not — unlike
// F3's node-kind conversion, there is no cost to converting a cold site here (the call is not longer,
// and the enum is what the gate's population arm can see). test/fieldidcheck.sh arm E holds that at
// zero remaining sites.

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>   // the compile-time row check reads each spelling's length

#include <tree_sitter/api.h>

namespace rw
{

// The field names the tree actually asks for, harvested from the call sites this header replaced.
// ORDER IS THE CONTRACT: kNodeFieldNames below is indexed by this enum, and the static_assert under it
// is what keeps a name added in one place and not the other from compiling. Alphabetical so a new field
// has one obvious home — the enum carries no meaning beyond being an index.
enum class NodeField : std::uint8_t
{
    Alias, Alternative, Argument, Arguments, Attribute,
    Body, Captures, Condition, Consequence, Constructor,
    Declaration, Declarator, DefaultValue, Definition, Directive,
    Expression, Field, Function, Initializer, Key, Left,
    Method, ModuleName, Name, Object, Operand, Operator,
    Parameter, Parameters, Path, Pattern, Property,
    Receiver, Right, Scope, Source, Subject,
    Superclasses, Target, Trait, Type, Update,
    Value,
    Op,
    Count
};

inline constexpr std::size_t kNodeFieldCount = static_cast<std::size_t>( NodeField::Count );

// The grammar spelling of each NodeField, and its length. The length is carried rather than recomputed
// because `ts_language_field_id_for_name` takes one and `std::strlen` on the fallback path would put the
// libc call back that this header exists to remove. Each row NAMES the enumerator it spells: the table is indexed by
// the enum, and a row that sits at another enumerator's index would hand every lookup after it its neighbour's field.
struct NodeFieldName
{
    NodeField     field;
    const char*   text;
    std::uint32_t len;
};

inline constexpr std::array<NodeFieldName, kNodeFieldCount> kNodeFieldNames = { {
    { NodeField::Alias, "alias", 5 },                 { NodeField::Alternative, "alternative", 11 },    { NodeField::Argument, "argument", 8 },
    { NodeField::Arguments, "arguments", 9 },         { NodeField::Attribute, "attribute", 9 },         { NodeField::Body, "body", 4 },
    { NodeField::Captures, "captures", 8 },           { NodeField::Condition, "condition", 9 },         { NodeField::Consequence, "consequence", 11 },
    { NodeField::Constructor, "constructor", 11 },    { NodeField::Declaration, "declaration", 11 },    { NodeField::Declarator, "declarator", 10 },
    { NodeField::DefaultValue, "default_value", 13 }, { NodeField::Definition, "definition", 10 },      { NodeField::Directive, "directive", 9 },
    { NodeField::Expression, "expression", 10 },      { NodeField::Field, "field", 5 },                 { NodeField::Function, "function", 8 },           { NodeField::Initializer, "initializer", 11 },
    { NodeField::Key, "key", 3 },                     { NodeField::Left, "left", 4 },                   { NodeField::Method, "method", 6 },
    { NodeField::ModuleName, "module_name", 11 },     { NodeField::Name, "name", 4 },                   { NodeField::Object, "object", 6 },
    { NodeField::Operand, "operand", 7 },             { NodeField::Operator, "operator", 8 },           { NodeField::Parameter, "parameter", 9 },
    { NodeField::Parameters, "parameters", 10 },      { NodeField::Path, "path", 4 },                   { NodeField::Pattern, "pattern", 7 },
    { NodeField::Property, "property", 8 },           { NodeField::Receiver, "receiver", 8 },           { NodeField::Right, "right", 5 },
    { NodeField::Scope, "scope", 5 },                 { NodeField::Source, "source", 6 },               { NodeField::Subject, "subject", 7 },
    { NodeField::Superclasses, "superclasses", 12 },  { NodeField::Target, "target", 6 },               { NodeField::Trait, "trait", 5 },
    { NodeField::Type, "type", 4 },                   { NodeField::Update, "update", 6 },               { NodeField::Value, "value", 5 },
    { NodeField::Op, "op", 2 },
} };

// ORDER, COUNT AND LENGTH, checked at compile time. The old assert compared kNodeFieldNames.size() with the extent the
// same declaration spells, which cannot fail: a row left out became a zero-filled { Alias, nullptr, 0 } tail, and a
// field inserted into the enum above a row the table did not move re-mapped every field after it. So every row must
// name the enumerator at its own index, carry a spelling, and declare that spelling's length. Returns the first
// offending INDEX and kNodeFieldCount when clean — never a spelling, which a zero-filled row can also produce.
constexpr std::size_t firstNodeFieldRowOutOfPlace() noexcept
{
    for( std::size_t index = 0; index < kNodeFieldNames.size(); ++index )
    {
        const NodeFieldName& row = kNodeFieldNames[index];
        if( row.field != static_cast<NodeField>( index ) || row.text == nullptr || row.len == 0
            || row.len != std::string_view( row.text ).size() )
        {
            return index;
        }
    }
    return kNodeFieldCount;
}
static_assert( firstNodeFieldRowOutOfPlace() == kNodeFieldCount,
               "kNodeFieldNames: a row is missing, out of order (it names another NodeField than its index) or declares a wrong length" );

// ---- the [grammar][field] table ------------------------------------------------------------------
//
// SoA, not a map: the scan reads ONLY the grammar pointers, so they live in their own contiguous array
// and the id blocks never share a cache line with them.
//
// THE CAPACITY IS NOT A SILENT CAP. It is 64 against 23 distinct grammars over 47 extension rows today,
// and ingest_crawl.h carries a static_assert that the crawl table's ROW count — an upper bound on its
// distinct-grammar count — fits here, so a 65th language is a COMPILE error rather than a run that is
// quietly slower. test/fieldidcheck.sh arm F is the second guard, on the distinct count. The runtime
// overflow arm in warmFieldIds below is therefore unreachable from the product; it is kept because a
// caller outside the crawl table would otherwise be silently wrong instead of silently slow, and slow is
// the honest failure here — an unregistered grammar keeps the by-name path, which is today's answer.
inline constexpr std::size_t kFieldIdCapacity = 64;

struct FieldIdRegistry
{
    std::array<const TSLanguage*, kFieldIdCapacity>                    lang{};   // scanned — hot
    std::array<std::array<TSFieldId, kNodeFieldCount>, kFieldIdCapacity> ids{};  // payload — read once, on the hit
    std::size_t                                                        count{ 0 };
};

// `constinit` is load-bearing, not decoration: a function-local static with dynamic initialization gets
// a guard variable, and the guard's acquire load would sit on the per-AST-node path this header exists
// to shorten. Zero-initialized aggregates need no guard, and constinit is what makes the compiler say so
// instead of leaving it to inspection.
inline FieldIdRegistry& fieldIdRegistry() noexcept
{
    static constinit FieldIdRegistry registry{};
    return registry;
}

// Resolve every NodeField for one grammar and install it. Idempotent. SINGLE-THREADED ONLY — see the
// THREADING note at the top of this file. A `lang` of nullptr (the grammar-less markdown rows in the
// crawl table) is a no-op, so a caller can hand the whole table over without filtering it first.
inline void warmFieldIds( const TSLanguage* lang )
{
    if( lang == nullptr )
    {
        return;
    }
    FieldIdRegistry& registry = fieldIdRegistry();
    for( std::size_t i = 0; i < registry.count; ++i )
    {
        if( registry.lang[ i ] == lang )
        {
            return;                                  // already warm — a second prewarm changes nothing
        }
    }
    if( registry.count >= kFieldIdCapacity )
    {
        return;                                      // full: this grammar keeps the by-name path (correct, just not faster)
    }
    const std::size_t slot = registry.count;
    for( std::size_t f = 0; f < kNodeFieldCount; ++f )
    {
        registry.ids[ slot ][ f ] = ts_language_field_id_for_name( lang, kNodeFieldNames[ f ].text, kNodeFieldNames[ f ].len );
    }
    registry.lang[ slot ] = lang;                    // published LAST: the pointer is what a reader scans for
    registry.count        = slot + 1;
}

// How many grammars are warm. For gates and for --doctor; never on a hot path.
inline std::size_t warmedGrammarCount() noexcept
{
    return fieldIdRegistry().count;
}

// The field id for ( grammar, field ) — the table's answer when the grammar is warm, and the same
// resolution the by-name call would have run when it is not. Never a wrong answer, only a slower one.
inline TSFieldId fieldIdFor( const TSLanguage* lang, NodeField field ) noexcept
{
    const std::size_t      f        = static_cast<std::size_t>( field );
    const FieldIdRegistry& registry = fieldIdRegistry();
    for( std::size_t i = 0; i < registry.count; ++i )
    {
        if( registry.lang[ i ] == lang )
        {
            return registry.ids[ i ][ f ];
        }
    }
    return ts_language_field_id_for_name( lang, kNodeFieldNames[ f ].text, kNodeFieldNames[ f ].len );
}

// `ts_node_child_by_field_name( n, kNodeFieldNames[field].text, …len )`, with the name resolution hoisted
// out of the per-node path. Same deref of `n`'s tree, same null-node answer for a field the grammar does
// not have, same node otherwise.
inline TSNode fieldChild( TSNode n, NodeField field ) noexcept
{
    return ts_node_child_by_field_id( n, fieldIdFor( ts_node_language( n ), field ) );
}

}   // namespace rw
