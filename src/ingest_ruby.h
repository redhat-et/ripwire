#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_ruby.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_ruby.h - Ruby's Rails/DSL capture lane, carved VERBATIM out of ingest_names.h and
// ingest_binds.h (2026-10-12, the extraction @mpapis offered on #339): the rendered db/schema.rb
// column capture (test/rubyschemacheck.sh; the one walker that dispatches it stays in the shared
// names section and reaches the minting through the existing forward declaration), the Jbuilder
// view typing, the class-side helper-method / singleton-accessor / mixin DSL walks and the
// FactoryBot walk (test/rubyrakejbuildercheck.sh, rubytypedrecvcheck.sh, rubyreachcheck.sh,
// rubyrspectargetcheck.sh). This is a per-language section in the ingest_elixir.h slot: it reopens
// `namespace rw` and the unnamed namespace inside it - one TU, one unnamed namespace, internal
// linkage unchanged, zero new API surface. The shared feature families (definitions, base
// relations, receiver classification, the bare-call walk) stay in the data-driven sections; what
// lives here is the Rails-DSL posture that genuinely differs.
namespace rw
{
namespace
{

// ─── the Rails schema capture (test/rubyschemacheck.sh): RUBY db/schema.rb COLUMNS ARE Section DEFS ───
// A schema file is recognized BY CONTENT, never by path: any Ruby file whose tree holds a
// `create_table "x", … do |t| … end` call — the call's `block:` field is a do_block whose `parameters:`
// field is a block_parameters carrying ONE bare identifier — is a rendered-schema document (the block
// is the create_table call's OWN do_block, found by named-child kind because the shared NodeField set
// has no Block enumerator). Path plays no part: a rendered dump sits at file level or under
// `ActiveRecord::Schema[].define … do`. WHAT A WALK OF THE FILE IS NOT: a MIGRATION wraps its
// create_table inside a class/module body, and rubySchemaTableCall's Gate 0 refuses every
// class/module-nested table — so the container DOES matter exactly there (the migration shape
// contributes ZERO defs, pinned by the three migration fixtures). The per-file signal (the walker's
// contains-"create_table" early-out in ingest_names.h) is a reject like the attribute-family capture's
// contains-"attr" reject; the semantic gate is the AST shape.
//
// Each `t.<type> "name"` / `t.<type> :name` receiver-CALL in the table's do-block body mints ONE
// SymKind::Section def at Lang::Ruby — the same data-kind slot as a YAML key / doc heading (model.h;
// note the wording change there: a Section is no longer "isolated in the graph" once these are
// Lang::Ruby and admit call edges) — with span = the name token and name = the literal (both quote
// spellings via stringLiteralText, or a simple_symbol's text minus ':'). The DSL CALLS keep their
// external-surface reference posture exactly like the attr family: no def named `string`/`datetime`
// appears. `t.timestamps` (a receiver call with NO arguments field) mints `created_at` AND `updated_at`
// — the DSL names them literally, symmetric with the id rule; the two defs anchor at the method
// token's start/end bytes, since no literal name tokens exist in the source.
//
// Non-column DSL — t.index / t.references / t.belongs_to / t.polymorphic — names no column and defines
// nothing (stated floor: `t.references :owner` would otherwise mint a phantom "owner" column). A column
// call whose receiver is not a bare identifier (`registry.string`, a receiver-less `string`) is not a
// column; a string named by a leading-comment-skipped FIRST argument is (the attribute-DSL comment posture).
//
// The id rule — the four grounded spellings, all pinned by test/rubyschemacheck.sh:
//   – no column named `id`, no `id:` pair, no primary_key pair    → an implicit `id` def anchored at
//     the TABLE-NAME string's content start (no `id` token exists; the anchor is per-table unique, so
//     the multi-def floor — `id` on N tables → --uses=id defs="N" — holds naturally)
//   – `id: false` (the pair VALUE is the anonymous `false` token)  → no id def (a key-less table)
//   – `id: :uuid` (pair value a simple_symbol)                     → `id` def AT THE PAIR KEY (the key's
//     text minus its trailing ':'; the uuid TYPE is not modelled — stated floor)
//   – `primary_key: "x"` (pair value a string)                     → a def named the string's content
//     instead of the implicit `id`
// Duplicate column NAMES across tables stay SEPARATE defs (distinct nameByte identities — the dedup
// ladder only folds same-byte captures).
inline constexpr std::array<std::string_view, 7> kRubySchemaNonColumns = { "index", "references", "belongs_to", "polymorphic", "check_constraint", "exclusion_constraint", "unique_constraint" };

// The FIRST non-comment named child of an argument_list — the attribute-DSL comment posture ("attribute( # note
// then :x"): a comment is an n-ary extra, never an argument. Null when the list is all comments/empty.
inline TSNode rubyFirstNonCommentArg( TSNode args ) noexcept
{
    ChildCursor cursor( args );
    TSNode      first{};
    bool        got = false;
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode c )
    {
        if( kindIs( ts_node_type( c ), "comment" ) )
        {
            return true;   // skip the comment train, keep looking
        }
        first = c;
        got   = true;
        return false;      // stop at the first real argument
    } );
    return got ? first : TSNode{};
}

// A pair node's KEY text: a hash_key_symbol carries its trailing ':' (the whole `force:` token) — strip
// it so the id/primary_key comparisons see the bare word. A key without the colon (already bare) passes
// through unchanged.
inline std::string_view rubyPairKeyText( TSNode pair, std::string_view src ) noexcept
{
    const TSNode       key = fieldChild( pair, NodeField::Key );
    std::string_view   t   = nodeTextOf( key, src );
    if( !t.empty() && t.back() == ':' )
    {
        t.remove_suffix( 1 );
    }
    return t;
}

// One `t.<method> <args>` receiver-call inside a table block: a Section def per the rules above. The
// RECEIVER must BE the block parameter the create_table call bound (`t` in a rendered schema's do |t|);
// any other bare identifier (`helper.string "x"`) is somebody's own helper call and names no column.
// The `sawId` out-param records an explicit `id` column so the implicit rule can see it.
inline void rubySchemaColumnCall( TSNode c, std::uint32_t fileId, std::string_view src, std::string_view receiverName, std::vector<RawDef>& defs, bool& sawId )
{
    if( !kindIs( ts_node_type( c ), "call" ) )
    {
        return;
    }
    const TSNode recv = fieldChild( c, NodeField::Receiver );
    if( ts_node_is_null( recv ) || !kindIs( ts_node_type( recv ), "identifier" ) || nodeTextOf( recv, src ) != receiverName )
    {
        return;   // receiver-less, receiver-qualified, or a DIFFERENT bare name: not a column on the block parameter
    }
    const std::string_view m = fieldIdentifierText( c, NodeField::Method, src );
    if( m.empty() )
    {
        return;
    }
    const std::uint32_t line = ts_node_start_point( c ).row + 1;
    if( m == "timestamps" && ts_node_is_null( fieldChild( c, NodeField::Arguments ) ) )
    {
        const TSNode     meth = fieldChild( c, NodeField::Method );
        const std::uint32_t s = ts_node_start_byte( meth ), e = ts_node_end_byte( meth );
        RawDef d;
        d.fileId = fileId; d.line = line; d.startByte = s; d.endByte = e; d.loc = 1;
        d.kind = SymKind::Section; d.lang = Lang::Ruby;
        d.nameByte = s;      d.name = "created_at"; defs.push_back( d );   // the two anchors are the
        d.nameByte = e;      d.name = "updated_at"; defs.push_back( d );   // method token's edges — no literal tokens exist
        return;
    }
    if( std::find( kRubySchemaNonColumns.begin(), kRubySchemaNonColumns.end(), m ) != kRubySchemaNonColumns.end() )
    {
        return;   // t.index / references / belongs_to / polymorphic name no column (stated floor)
    }
    const TSNode args = fieldChild( c, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        return;
    }
    const TSNode nameNode = rubyFirstNonCommentArg( args );
    if( ts_node_is_null( nameNode ) )
    {
        return;
    }
    const std::string lit = stringLiteralText( nameNode, src );   // "" when not a string node
    std::string_view txt = lit;
    if( txt.empty() && kindIs( ts_node_type( nameNode ), "simple_symbol" ) )
    {
        txt = nodeTextOf( nameNode, src );
        if( txt.size() > 1 && txt.front() == ':' )
        {
            txt.remove_prefix( 1 );
        }
    }
    if( txt.empty() )
    {
        return;   // `""` / `: ` defensive: an empty name is no column
    }
    const std::uint32_t s = ts_node_start_byte( nameNode ), e = ts_node_end_byte( nameNode );
    RawDef d;
    d.fileId = fileId; d.line = line; d.startByte = s; d.endByte = e; d.loc = 1;
    d.kind = SymKind::Section; d.lang = Lang::Ruby; d.nameByte = s + 1;   // content start — past the quote or ':'
    d.name = std::string( txt );
    if( d.name == "id" )
    {
        sawId = true;
    }
    defs.push_back( d );
}

// A create_table call read as a rendered schema's table (the gates below): its string name, its arguments, its own do_block
// and the block parameter its column calls must use. A null name when `n` is not one.
struct RubySchemaTable
{
    TSNode           name {};
    TSNode           args {};
    TSNode           block {};
    std::string_view handle;   // the `|t|` spelling
};

inline RubySchemaTable rubySchemaTableOf( TSNode n, std::string_view src )
{
    // Gate 0: a rendered schema's tables live at file level or under `ActiveRecord::Schema[].define … do`
    // — NEVER inside a class/module body. A MIGRATION's `create_table "users" … do |t|` (class-wrapped,
    // often string-named) is the same AST shape, and without this gate it would mint the SAME columns as
    // the schema that migration created — double-counting every added column on every corpus with both
    // files indexed. `add_column`/`remove_column` are not read anywhere (a column added then dropped never
    // registers; pinned by the migration fixtures), but the create_table of a real migration must not
    // double its schema either. Excluding at least one `class`/`module` ancestor keeps the capture
    // content-gated (still no path heuristic): a migration file next to the schema contributes ZERO defs.
    // Checked FIRST — the cheapest gate — before the argument/block walks.
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const std::string_view k( ts_node_type( p ) );
        if( k == "class" || k == "module" )   // a locals distilled walk — no cross-helper dependency
        {
            return {};
        }
    }
    RubySchemaTable t;
    t.args = fieldChild( n, NodeField::Arguments );
    if( ts_node_is_null( t.args ) )
    {
        return {};
    }
    // Gate 1: a STRING table name as the first argument (a symbol-named table is a migration spelling,
    // not a rendered-schema shape — stated floor; no name node → no schema surface either).
    const TSNode tableName = rubyFirstNonCommentArg( t.args );
    if( ts_node_is_null( tableName ) || !kindIs( ts_node_type( tableName ), "string" ) )
    {
        return {};
    }
    // Gate 2: the call's OWN do_block, and its parameters: field carries ONE bare identifier (the `|t|`).
    {
        ChildCursor cursor( n );
        forEachNamedChild( n, cursor.cur, [ & ]( TSNode c )
        {
            if( kindIs( ts_node_type( c ), "do_block" ) )
            {
                t.block = c;
                return false;
            }
            return true;
        } );
    }
    const TSNode params = ts_node_is_null( t.block ) ? TSNode{} : fieldChild( t.block, NodeField::Parameters );
    if( ts_node_is_null( params ) )
    {
        return {};   // no block, or `create_table "x" do … end` with no handle — not the schema shape
    }
    ChildCursor cursor( params );
    TSNode      only{};
    std::size_t named = 0;
    forEachNamedChild( params, cursor.cur, [ & ]( TSNode c ) { only = c; ++named; return true; } );
    if( named != 1 || !kindIs( ts_node_type( only ), "identifier" ) )
    {
        return {};   // multi-parameter or non-identifier handle — not a rendered schema's do |t|
    }
    t.handle = nodeTextOf( only, src );   // the `|t|` spelling — column calls must use it
    t.name   = tableName;
    return t;
}

// One create_table call: the schema-file gate plus the whole table's defs (name, options, columns, id).
inline void rubySchemaTableCall( TSNode n, std::uint32_t fileId, std::string_view src, std::vector<RawDef>& defs )
{
    const RubySchemaTable table = rubySchemaTableOf( n, src );
    if( ts_node_is_null( table.name ) )
    {
        return;
    }
    const TSNode           args         = table.args;
    const TSNode           block        = table.block;
    const TSNode           tableName    = table.name;
    const std::string_view receiverName = table.handle;
    // Options: the id/primary_key pairs among the call's arguments.
    bool   idFalse = false, primaryKey = false;
    TSNode idKey{}, pkValue{};
    {
        ChildCursor cursor( args );
        forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
        {
            if( !kindIs( ts_node_type( a ), "pair" ) )
            {
                return true;
            }
            const std::string_view k = rubyPairKeyText( a, src );
            const TSNode           v = fieldChild( a, NodeField::Value );
            if( k == "id" )
            {
                if( kindIs( ts_node_type( v ), "false" ) )
                {
                    idFalse = true;
                }
                else if( kindIs( ts_node_type( v ), "simple_symbol" ) )
                {
                    idKey = fieldChild( a, NodeField::Key );
                }
            }
            else if( k == "primary_key" )
            {
                primaryKey = true;
                pkValue    = v;
            }
            return true;
        } );
    }
    // The columns: the do_block's body: field (its body_statement) — walk its named children directly
    // (a fresh cursor; the outer walks cannot be reused mid-flight, tschildren.h).
    bool sawIdColumn = false;
    const TSNode body = fieldChild( block, NodeField::Body );
    if( !ts_node_is_null( body ) )
    {
        ChildCursor cursor( body );
        forEachNamedChild( body, cursor.cur, [ & ]( TSNode c )
        {
            rubySchemaColumnCall( c, fileId, src, receiverName, defs, sawIdColumn );
            return true;
        } );
    }
    // The id rule, in the grounded order: an explicit id column wins; then the pairs decide.
    if( sawIdColumn || idFalse )
    {
        return;
    }
    if( primaryKey && !ts_node_is_null( pkValue ) && kindIs( ts_node_type( pkValue ), "string" ) )
    {
        const std::string name = stringLiteralText( pkValue, src );
        if( name.empty() )
        {
            return;
        }
        const std::uint32_t s = ts_node_start_byte( pkValue ), e = ts_node_end_byte( pkValue );
        RawDef d;
        d.fileId = fileId; d.line = ts_node_start_point( pkValue ).row + 1; d.startByte = s; d.endByte = e; d.loc = 1;
        d.kind = SymKind::Section; d.lang = Lang::Ruby; d.nameByte = s + 1; d.name = name;
        defs.push_back( d );
        return;
    }
    if( !ts_node_is_null( idKey ) )
    {
        const std::uint32_t s = ts_node_start_byte( idKey ), e = ts_node_end_byte( idKey );
        RawDef d;
        d.fileId = fileId; d.line = ts_node_start_point( idKey ).row + 1; d.startByte = s; d.endByte = e; d.loc = 1;
        d.kind = SymKind::Section; d.lang = Lang::Ruby; d.nameByte = s; d.name = "id";
        defs.push_back( d );
        return;
    }
    // A primary_key pair with a NON-string value (composite `["a","b"]`, hand-written `:symbol`): the
    // key is NOT an `id` and the rendered columns are the block's own explicit `t.<type>` lines (already
    // minted above) — suppress the implicit id entirely (the composite case is pinned by the fixture).
    if( primaryKey )
    {
        return;
    }
    // Implicit `id` — anchored at the table-name string's content start (a stable per-table byte).
    {
        const std::uint32_t s = ts_node_start_byte( tableName ), e = ts_node_end_byte( tableName );
        RawDef d;
        d.fileId = fileId; d.line = ts_node_start_point( tableName ).row + 1; d.startByte = s; d.endByte = e; d.loc = 1;
        d.kind = SymKind::Section; d.lang = Lang::Ruby; d.nameByte = s + 1; d.name = "id";
        defs.push_back( d );
    }
}


// ─── A Jbuilder template's `json`, and `helper_method` (test/rubyrakejbuildercheck.sh, parser version 135) ─────────────
// graph.h RubyTopSelf reads a template's self outside any class as the view. The template handler binds `json` there to the
// view's JbuilderTemplate (model.h kJbuilderTemplate), whose method_missing makes every name a key: a read of it is no
// call, and a call on it is typed that class. A `helper_method :a, :b` at class-body position names methods of the class
// its views call, recorded as LocalBindKind::RubyHelperMethod bindings against the declaring class or module (a concern's
// `included do` block declares for the concern, whose def it is).

// Over a template's references — the trailing run carrying this fileId: the bare-word `json` reads dropped, and each call
// on `json` typed JbuilderTemplate.
inline void typeRubyJbuilderLocal( std::uint32_t fileId, std::vector<RawRef>& refs )
{
    std::size_t first = refs.size();
    while( first > 0 && refs[ first - 1 ].fileId == fileId )
    {
        --first;
    }
    const auto read = []( const RawRef& r ) { return r.role == RefRole::Call && r.recv == RecvKind::None && r.name == kJbuilderLocal; };
    refs.erase( std::remove_if( refs.begin() + std::ptrdiff_t( first ), refs.end(), read ), refs.end() );
    for( std::size_t i = first; i < refs.size(); ++i )
    {
        if( refs[ i ].role == RefRole::Call && refs[ i ].recv == RecvKind::NamedVar && refs[ i ].recvVar == kJbuilderLocal )
        {
            rubyTypeReceiver( refs[ i ], kJbuilderTemplate, kJbuilderLocal, false );
        }
    }
}

// Does `call` sit at class-body position — its nearest enclosing def-or-class a class or module, any blocks between?
inline bool rubyAtClassBody( TSNode call ) noexcept
{
    for( TSNode p = ts_node_parent( call ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( kindIs( t, "class" ) || kindIs( t, "module" ) )
        {
            return true;
        }
        if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) || kindIs( t, "singleton_class" ) )
        {
            return false;
        }
    }
    return false;
}

// One binding per symbol argument in `args` (`helper_method :a, :b`, `attr_accessor :c`): `like` with the symbol's own start
// byte and its name (the colon dropped).
inline void rubyNoteSymbolArguments( TSNode args, const RawBind& like, std::string_view src, std::vector<RawBind>& binds )
{
    if( ts_node_is_null( args ) )
    {
        return;
    }
    ChildCursor cursor( args );   // O(children) (src/infra/tschildren.h)
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        if( kindIs( ts_node_type( a ), "simple_symbol" ) )
        {
            RawBind b   = like;
            b.startByte = ts_node_start_byte( a );
            b.var       = std::string( pattern::nodeText( a, src ).substr( 1 ) );
            binds.push_back( std::move( b ) );
        }
        return true;
    } );
}

// Each symbol of the `helper_method` call `call`, a binding against the class or module around it.
inline void rubyNoteHelperMethods( TSNode call, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const std::string owner = rubyEnclosingScopeOf( call, src );
    if( !owner.empty() )
    {
        rubyNoteSymbolArguments( fieldChild( call, NodeField::Arguments ),
                                 RawBind { .fileId = fileId, .lang = Lang::Ruby, .kind = LocalBindKind::RubyHelperMethod, .typeName = owner }, src, binds );
    }
}

// Every node of a Ruby file's tree, handed to `take` in turn; a node `take` returns true for is taken, and its subtree is
// not walked. Iterative, so a hostile nesting depth costs heap, not stack.
template<class Take>
inline void rubyWalkUntaken( TSNode root, Take&& take )
{
    std::vector<TSNode> stack { root };
    std::vector<TSNode> kids;
    ChildCursor         cursor( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        if( !take( n ) )
        {
            collectChildren( n, cursor.cur, kids );
            stack.insert( stack.end(), kids.begin(), kids.end() );
        }
    }
}

// One file's `helper_method` declarations, into `binds` — a file that never spells the word is not walked (rubyWalkUntaken).
inline void captureRubyHelperMethods( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "helper_method" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const bool declares = kindIs( ts_node_type( n ), "call" ) && ts_node_is_null( fieldChild( n, NodeField::Receiver ) )
                           && fieldChildTextOfKind( n, NodeField::Method, "identifier", src ) == "helper_method";
        if( declares && rubyAtClassBody( n ) )
        {
            rubyNoteHelperMethods( n, fileId, src, binds );
            return true;
        }
        return false;
    } );
}

// Parser version 137 (test/rubyclassrecvcheck.sh): is the Ruby def `defNode` a SINGLETON method — `def self.m`, or a def
// inside `class << self` — which a call on a class object answers and no instance's lookup reaches? The nearest class,
// module or def above a plain `def` decides; a block between them (`class_methods do`, `included do`) is walked through.
// rubyDefSide below tells whose class object; captureRubyClassMixins reads a directive in `class << self` with this.
inline bool rubyIsSingletonDef( TSNode defNode ) noexcept
{
    if( kindIs( ts_node_type( defNode ), "singleton_method" ) )
    {
        const TSNode object = fieldChild( defNode, NodeField::Object );
        return !ts_node_is_null( object ) && kindIs( ts_node_type( object ), "self" );
    }
    for( TSNode n = ts_node_parent( defNode ); !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "singleton_class" ) )
        {
            const TSNode value = fieldChild( n, NodeField::Value );
            return !ts_node_is_null( value ) && kindIs( ts_node_type( value ), "self" );
        }
        if( kindIs( t, "class" ) || kindIs( t, "module" ) || kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            return false;
        }
    }
    return false;
}

// What a Ruby def is to a class object (parser versions 137 and 145; test/rubyclassrecvcheck.sh).
enum class RubyDefSide : std::uint8_t
{
    Instance,    // an instance method: no call on a class object reaches it
    Singleton,   // a singleton method of the class or module that holds it — `def self.m`, a def or an accessor in `class << self`
    Includer,    // a class method of each class INCLUDING its module, defined on the includer itself: a singleton def inside a
                 //   concern's `included do`, which runs on the includer
    ClassMethods,   // a class method of each includer from a module extended onto it: a def inside a concern's `class_methods
                    //   do`, which ActiveSupport::Concern makes the concern's ClassMethods
};

// The two blocks of an ActiveSupport::Concern whose defs can be its includer's class methods (RubyDefSide::Includer,
// ClassMethods).
inline constexpr std::array<std::string_view, 2> kRubyIncluderBlocks = { "included", "class_methods" };

// The concern hook (kRubyIncluderBlocks) whose block `n` is, written at class-body level, or empty.
inline std::string_view rubyIncluderHook( TSNode n, std::string_view src ) noexcept
{
    const TSNode owner = kindIs( ts_node_type( n ), "do_block" ) || kindIs( ts_node_type( n ), "block" ) ? ts_node_parent( n ) : TSNode {};
    if( ts_node_is_null( owner ) || !kindIs( ts_node_type( owner ), "call" ) )
    {
        return {};
    }
    const std::string_view hook = rubyNamedDirective( owner, src, kRubyIncluderBlocks );
    return !hook.empty() && rubyAttrAtClassBodyLevel( owner, src ) ? hook : std::string_view {};
}

// What a def written in a concern's `hook` block is: in `included do`, a singleton def is the includer's own and a plain
// one an instance method; in `class_methods do`, a plain def is the includer's class method.
inline RubyDefSide rubyHookSide( std::string_view hook, bool singleton ) noexcept
{
    if( hook == "included" )
    {
        return singleton ? RubyDefSide::Includer : RubyDefSide::Instance;
    }
    return singleton ? RubyDefSide::Instance : RubyDefSide::ClassMethods;
}

// What the Ruby def — or `class << self` accessor — at `defNode` is to a class object. A `def self.m`, or a `class << self`
// above it, makes it a singleton method, and the nearest class, module or def above decides whose — unless a concern's
// `included do` (for a singleton def) or `class_methods do` (for a plain one) at class-body level comes first, which makes
// it the includer's: defined on the includer itself, or in the module the concern extends onto it. Any other block between
// is walked through.
inline RubyDefSide rubyDefSide( TSNode defNode, std::string_view src ) noexcept
{
    const bool selfDef = kindIs( ts_node_type( defNode ), "singleton_method" );
    if( selfDef && fieldChildTextOfKind( defNode, NodeField::Object, "self", src ).empty() )
    {
        return RubyDefSide::Instance;   // `def obj.m` is another object's
    }
    bool singleton = selfDef;
    for( TSNode n = ts_node_parent( defNode ); !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "singleton_class" ) )
        {
            if( fieldChildTextOfKind( n, NodeField::Value, "self", src ).empty() )
            {
                return RubyDefSide::Instance;   // `class << Other` opens another object's singleton
            }
            singleton = true;
            continue;
        }
        if( kindIs( t, "class" ) || kindIs( t, "module" ) || kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            break;
        }
        if( const std::string_view hook = rubyIncluderHook( n, src ); !hook.empty() )
        {
            return rubyHookSide( hook, singleton );
        }
    }
    return singleton ? RubyDefSide::Singleton : RubyDefSide::Instance;
}

// The importedName a Ruby class-object binding carries for a def on `side` (model.h LocalBindKind::RubySingletonDef).
inline std::string rubySideMark( RubyDefSide side )
{
    return std::string( side == RubyDefSide::Includer ? kRubyIncluderMark : side == RubyDefSide::ClassMethods ? kRubyClassMethodsMark : std::string_view {} );
}

// A LocalBindKind::RubySingletonDef binding for the def at `defNode` named `name`, when a class object answers it: a
// singleton method (parser version 137), or a class method of each includer (parser version 145).
inline void rubyNoteClassSideDef( TSNode defNode, std::uint32_t fileId, std::string_view name, std::string_view src, std::vector<RawBind>& binds )
{
    const RubyDefSide side = rubyDefSide( defNode, src );
    if( side != RubyDefSide::Instance )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( defNode ), .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef,
                                   .var = std::string( name ), .importedName = rubySideMark( side ) } );
    }
}

// The bindings for what the `class << self` call `n` declares on the class object's `side` — an accessor, or a
// delegation-DSL call (captureRubySingletonAccessors below). An accessor's binding sits at its symbol,
// where captureRubyDefs starts its def (no owner), and carries the side's mark (one a concern's `included do`
// declares is the includer's); a delegated name has no def, and is read against the class that owns the singleton.
inline void rubyNoteSingletonDecl( TSNode n, RubyDefSide side, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const std::string_view delegation = rubyNamedDirective( n, src, kRubyDelegationCalls );
    if( delegation.empty() )
    {
        rubyNoteSymbolArguments( fieldChild( n, NodeField::Arguments ),
                                 RawBind { .fileId = fileId, .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef, .importedName = rubySideMark( side ) },
                                 src, binds );
        return;
    }
    const std::string owner = rubyEnclosingScopeOf( n, src );
    if( delegation == "delegate_missing_to" )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( n ), .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef, .typeName = owner } );
        return;
    }
    rubyNoteSymbolArguments( fieldChild( n, NodeField::Arguments ), RawBind { .fileId = fileId, .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef, .typeName = owner },
                             src, binds );
}

// What a `class << self` declares beside its defs is the class object's too (parser version 137): each accessor
// (`attr_accessor :config`, one RubySingletonDef binding per name, where captureRubyDefs starts its def) and each name
// the delegation DSL defines (model.h kRubyDelegationCalls — `delegate :reset, to: :instance`: a binding per name against
// the owning class; `delegate_missing_to` one with no name, as it answers every name). A file that never writes `<<` is not
// walked; the walk is iterative, so a hostile nesting depth costs heap, not stack.
inline void captureRubySingletonAccessors( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "<<" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const bool        call     = kindIs( ts_node_type( n ), "call" );
        const bool        declares = call && ( !rubyNamedDirective( n, src, kRubyAttrFamilyNames ).empty() || !rubyNamedDirective( n, src, kRubyDelegationCalls ).empty() );
        const RubyDefSide side     = declares && rubyAttrAtClassBodyLevel( n, src ) ? rubyDefSide( n, src ) : RubyDefSide::Instance;
        if( side == RubyDefSide::Instance )
        {
            return false;
        }
        rubyNoteSingletonDecl( n, side, fileId, src, binds );
        return true;
    } );
}

// Parser version 145 (test/rubyclassrecvcheck.sh): each mixin the CLASS OBJECT's lookup reaches rather than its
// instances' — the constants of an `extend M`, and of an `include`/`prepend` inside `class << self` — as a
// LocalBindKind::RubyClassMixin binding at the constant's own start byte, where emitCapturedRubyMixinBase puts its inherit
// reference, read where that reads the directive (class-body level, or a concern's `included do`). One a concern's
// `included do` writes extends the includer, not the concern: importedName kRubyIncluderMark. A class body's `extend self`
// names no constant: its binding sits at the directive, var "self". A file that never writes `extend` or `<<` is not
// walked, and the walk enters no def, whose body holds no directive.
// Is the mixin directive `n` an `extend self` — its one argument `self`?
inline bool rubyExtendsSelf( TSNode n ) noexcept
{
    const TSNode args = fieldChild( n, NodeField::Arguments );
    return !ts_node_is_null( args ) && ts_node_named_child_count( args ) == 1 && kindIs( ts_node_type( ts_node_named_child( args, 0 ) ), "self" );
}

// The RubyClassMixin bindings of the mixin directive `n` (an `extend` when `extend`), read where emitCapturedRubyMixinBase reads
// it: one per constant a class object's lookup reaches, and a module body's `extend self`.
inline void rubyNoteClassMixins( TSNode n, bool extend, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const bool inIncluded = rubyInConcernIncludedBlock( n, src );
    if( !inIncluded && !rubyAttrAtClassBodyLevel( n, src ) )
    {
        return;
    }
    const bool singleton = rubyIsSingletonDef( n );   // the directive sits in `class << self`
    if( extend && !inIncluded && !singleton && rubyExtendsSelf( n ) )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( n ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyClassMixin, .var = "self" } );
    }
    if( extend == singleton )
    {
        return;   // an include joins the instances' lookup, an extend inside `class << self` the singleton's own
    }
    const bool includer = inIncluded || ( singleton && rubyDefSide( n, src ) == RubyDefSide::Includer );
    for( const TSNode c : rubyMixinTargets( n, src ) )
    {
        binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( c ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyClassMixin,
                                   .importedName = includer ? std::string( kRubyIncluderMark ) : std::string {} } );
    }
}

inline void captureRubyClassMixins( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "extend" ) == std::string_view::npos && src.find( "<<" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            return true;   // a def body holds no directive
        }
        const std::string_view verb = kindIs( t, "call" ) ? rubyNamedDirective( n, src, kRubyConstantDirectives ) : std::string_view {};
        if( verb.empty() || verb == "autoload" )
        {
            return false;
        }
        rubyNoteClassMixins( n, verb == "extend", fileId, src, binds );
        return true;
    } );
}

// Parser version 174 (lane ruby-pair; test/subscriptopcheck.sh): a TOP-LEVEL `include M` / `extend M` / `self.extend M`.
// Outside every class and module, self is Ruby's main object, and these make it answer M's methods — rake extends main
// with Rake::DSL so a Rakefile's bare `task` / `file` reach it. graph.h lists main as M's implementor (`<impl t="object"
// n="main">`). Ruby-only: main is Ruby's top-level self; no other indexed language has an object that a file's top level
// mixes a module into (Python/JS module scope is a namespace, not an instance). Read: a statement of the program itself,
// receiver-less or on `self`, and each constant argument. Not read (stated floors, test/subscriptopcheck.sh): a
// directive inside a top-level `if` / `begin` or a block, `prepend` (main has none), a non-constant argument.
inline void captureRubyMainMixins( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( ts_node_is_null( root ) || ( src.find( "extend" ) == std::string_view::npos && src.find( "include" ) == std::string_view::npos ) )
    {
        return;
    }
    ChildCursor cursor( root );
    forEachNamedChild( root, cursor.cur, [ & ]( TSNode n )
    {
        if( !kindIs( ts_node_type( n ), "call" ) )
        {
            return true;
        }
        const TSNode           recv = fieldChild( n, NodeField::Receiver );
        const std::string_view verb = fieldIdentifierText( n, NodeField::Method, src );
        if( ( verb != "include" && verb != "extend" ) || !( ts_node_is_null( recv ) || kindIs( ts_node_type( recv ), "self" ) ) )
        {
            return true;
        }
        for( const TSNode c : rubyConstantArguments( n ) )
        {
            binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( c ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyMainMixin,
                                       .spanStart = ts_node_start_point( c ).row + 1, .importedName = std::string( verb ),
                                       .typeName = rubyConstantText( c, src ) } );
        }
        return true;
    } );
}

// ─── RSpec example groups (parser version 273, test/rubygroupselfcheck.sh) ─────────────────────────────────────────────
// Inside an example group's block self is the group's — the group class at its own body, an example inside `it`, `let` or
// `before` — and graph.h RubyTopSelf answers a receiver-less call there from that lookup instead of the name tier. This
// pass records what the lookup needs (model.h LocalBindKind::RubyGroupSelf / RubyGroupMixin): one span per OUTERMOST group
// block and per `RSpec.configure` block (its hooks run on examples), the shared groups and the configure blocks marked as
// the ones whose defs every group reaches; one hole span per block inside them that hands self
// to another object; and one mixin per module the groups take in — `config.include M` on the configure block's parameter,
// `include M` written as a statement of a group's own body. Ruby-only: the block whose self a test framework replaces is
// RSpec's, and the language with no explicit receiver for it is Ruby.

// The blocks whose self is another object: `x.instance_eval { }` and its kin, and a class or record built from a block.
inline constexpr std::string_view kRubySelfRebinders[]   = { "class_eval", "class_exec", "instance_eval", "instance_exec", "module_eval", "module_exec" };
inline constexpr std::string_view kRubyBlockClassMakers[] = { "Class", "Data", "Module", "Struct" };   // `Class.new do … end`, `Data.define do … end`

// Is call `n`'s block run with another object as self?
inline bool rubyRebindsSelf( TSNode n, std::string_view src )
{
    const std::string_view m = fieldIdentifierText( n, NodeField::Method, src );
    if( std::ranges::find( kRubySelfRebinders, m ) != std::end( kRubySelfRebinders ) )
    {
        return true;
    }
    const TSNode recv = fieldChild( n, NodeField::Receiver );
    return ( m == "new" || m == "define" ) && !ts_node_is_null( recv ) && kindIs( ts_node_type( recv ), "constant" )
        && std::ranges::find( kRubyBlockClassMakers, pattern::nodeText( recv, src ) ) != std::end( kRubyBlockClassMakers );
}

// Is call `n` `RSpec.configure`?
inline bool rspecConfigureCall( TSNode n, std::string_view src )
{
    const TSNode recv = fieldChild( n, NodeField::Receiver );
    return !ts_node_is_null( recv ) && kindIs( ts_node_type( recv ), "constant" ) && pattern::nodeText( recv, src ) == "RSpec"
        && fieldIdentifierText( n, NodeField::Method, src ) == "configure";
}

// The one identifier parameter of `block` (`do |config|`), or empty.
inline std::string_view rubyBlockSoleParam( TSNode block, std::string_view src )
{
    const TSNode params = fieldChild( block, NodeField::Parameters );
    if( ts_node_is_null( params ) )
    {
        return {};
    }
    ChildCursor cursor( params );
    TSNode      only{};
    std::size_t named = 0;
    forEachNamedChild( params, cursor.cur, [ & ]( TSNode c ) { only = c; ++named; return true; } );
    return named == 1 && kindIs( ts_node_type( only ), "identifier" ) ? nodeTextOf( only, src ) : std::string_view {};
}

// The modules `block`'s own statements mix into the groups, as LocalBindKind::RubyGroupMixin records: `<param>.include M`
// when `param` names the configure block's parameter, else (a group's body) a receiver-less `include M`. A statement only:
// `expect( x ).to include( Foo )` is RSpec's matcher, an argument, never one.
inline void rubyNoteGroupMixins( TSNode block, bool configure, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const std::string_view param = configure ? rubyBlockSoleParam( block, src ) : std::string_view {};
    const TSNode           body  = fieldChild( block, NodeField::Body );
    if( ts_node_is_null( body ) || ( configure && param.empty() ) )
    {
        return;
    }
    ChildCursor cursor( body );
    forEachNamedChild( body, cursor.cur, [ & ]( TSNode c )
    {
        if( !kindIs( ts_node_type( c ), "call" ) || fieldIdentifierText( c, NodeField::Method, src ) != "include" )
        {
            return true;
        }
        const TSNode recv = fieldChild( c, NodeField::Receiver );
        const bool   mine = configure ? !ts_node_is_null( recv ) && kindIs( ts_node_type( recv ), "identifier" ) && pattern::nodeText( recv, src ) == param
                                      : ts_node_is_null( recv );
        for( const TSNode a : mine ? rubyConstantArguments( c ) : std::vector<TSNode> {} )
        {
            binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( a ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyGroupMixin,
                                       .typeName = rubyConstantText( a, src ) } );
        }
        return true;
    } );
}

// The constant an outermost group describes (`RSpec.describe BadgeHelper`), as a RubyGroupMixin marked kRubyGroupHelperMark
// when the group says `type: :helper` and kRubyGroupDescribedMark otherwise: rspec-rails mixes a helper spec's module into
// its groups, and graph.h keeps the unmarked kind only where the location says helper spec (ruby_groupself.h).
inline void rubyNoteDescribedModule( TSNode call, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const TSNode args  = fieldChild( call, NodeField::Arguments );
    const TSNode first = ts_node_is_null( args ) ? args : ts_node_named_child( args, 0 );
    if( ts_node_is_null( first ) || !isRubyConstantNode( first ) )
    {
        return;
    }
    bool        helper = false;
    ChildCursor cursor( args );
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        const TSNode v = kindIs( ts_node_type( a ), "pair" ) && rubyPairKeyText( a, src ) == "type" ? fieldChild( a, NodeField::Value ) : TSNode {};
        helper         = helper || ( !ts_node_is_null( v ) && nodeTextOf( v, src ) == ":helper" );
        return true;
    } );
    binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( first ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyGroupMixin,
                               .importedName = std::string( helper ? kRubyGroupHelperMark : kRubyGroupDescribedMark ), .typeName = rubyConstantText( first, src ) } );
}

// One block's RubyGroupSelf span, marked (a shared group's or a configure block's, a hole) or not (a group's).
inline void rubyNoteGroupSpan( TSNode block, std::string_view mark, std::uint32_t fileId, std::vector<RawBind>& binds )
{
    binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( block ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyGroupSelf,
                               .spanStart = ts_node_start_byte( block ), .spanEnd = ts_node_end_byte( block ), .importedName = std::string( mark ) } );
}

// A group or configure call `n`: the modules its block's statements mix in, and — when no group encloses it — its span (a
// shared group's and a configure block's marked) and the constant a plain group describes.
inline void rubyNoteExampleGroup( TSNode n, bool outermost, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    const TSNode block = rubyCallBlock( n );
    const int    kind  = rspecGroupKind( n, src );   // 0: the configure block
    rubyNoteGroupMixins( block, kind == 0, fileId, src, binds );
    if( !outermost )
    {
        return;
    }
    rubyNoteGroupSpan( block, kind == 1 ? std::string_view {} : kRubyGroupSharedMark, fileId, binds );
    if( kind == 1 )
    {
        rubyNoteDescribedModule( n, fileId, src, binds );
    }
}

// The walk: an explicit stack, so a deep nest costs heap, not the worker's stack. A group or configure call's block is
// walked as the group's; inside it a self-rebinding block is recorded as a hole and not walked further — a group written
// inside one is that object's business.
inline void captureRubyExampleGroups( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    static constexpr std::string_view kWords[] = { "describe", "context", "feature", "example_group", "shared_", "configure" };
    const auto mentions = [ & ]( std::string_view w ) { return src.find( w ) != std::string_view::npos; };
    if( ts_node_is_null( root ) || std::none_of( std::begin( kWords ), std::end( kWords ), mentions ) )
    {
        return;
    }
    std::vector<std::pair<TSNode, bool>> stack { { root, false } };   // (node, inside a group)
    while( !stack.empty() )
    {
        const auto [ n, inGroup ] = stack.back();
        stack.pop_back();
        const TSNode block = kindIs( ts_node_type( n ), "call" ) ? rubyCallBlock( n ) : TSNode {};
        if( !ts_node_is_null( block ) && ( rspecGroupKind( n, src ) != 0 || rspecConfigureCall( n, src ) ) )
        {
            rubyNoteExampleGroup( n, !inGroup, fileId, src, binds );
            stack.emplace_back( block, true );
            continue;
        }
        if( !ts_node_is_null( block ) && inGroup && rubyRebindsSelf( n, src ) )
        {
            rubyNoteGroupSpan( block, kRubyGroupHoleMark, fileId, binds );
            continue;
        }
        ChildCursor cursor( n );
        forEachNamedChild( n, cursor.cur, [ & ]( TSNode c ) { stack.emplace_back( c, inGroup ); return true; } );
    }
}

// ─── Methods Ruby generates (parser version 277, test/rubygeneratedcheck.sh; src/ruby_generated.h) ─────────────────────
// A declaration at a class body's level — or in a concern's `included do`, which runs on each includer — defines the methods
// src/ruby_generated.h kRubyGeneratedVerbs lists for it: `has_many :bills` defines `bills` and `bills=`. Each is
// minted as a Section definition of the class or concern (captureRubyGeneratedDefs), the token that names it its extent;
// the class methods among them (a scope, an enum value's scope) carry a RubySingletonDef binding named for them
// (captureRubyGeneratedSides). One declaration mints several definitions from one token, so each takes as its name byte the
// declaration's start plus its own position among them — a byte inside the declaration that no other definition names —
// and a Section is never held to the head rule (extentsuspect.h). Not read: a declaration in `class << self` (the class
// object's own, which graph.h's delegation reading answers), inside a def or any block but `included do` (`with_options`:
// test/rubygeneratedcheck.sh floor (d)), Active Record's in a plain module's body, and an argument that is no symbol or plain
// string (a computed name).

// One generated method: its name, the token that names it, its side, and whether a concern's `included do` declares it (a
// class method there is each includer's).
struct RubyGenMethod
{
    std::string name;
    TSNode      token;
    RubyGenSide side     = RubyGenSide::Instance;
    bool        includer = false;
};

// Where one declaration's methods go: the list, and whether a concern's `included do` holds the declaration.
struct RubyGenSink
{
    std::vector<RubyGenMethod>& out;
    bool                        includer = false;

    // Each `names` method generated from the name `n` its token spells.
    void from( std::string_view n, TSNode token, std::span<const RubyGenName> names ) const
    {
        for( const RubyGenName& g : n.empty() ? std::span<const RubyGenName> {} : names )
        {
            out.push_back( RubyGenMethod { std::string( g.prefix ).append( n ).append( g.suffix ), token, g.side, includer } );
        }
    }
};

// The name a symbol (`:a`) or a plain string (`"a"`, no interpolation) argument spells, or empty.
inline std::string_view rubyGenArgName( TSNode a, std::string_view src ) noexcept
{
    const char* t = ts_node_type( a );
    if( kindIs( t, "simple_symbol" ) )
    {
        const std::string_view text = nodeTextOf( a, src );
        return text.empty() ? text : text.substr( 1 );   // a recovered parse can leave a zero-width symbol
    }
    if( kindIs( t, "hash_key_symbol" ) || kindIs( t, "identifier" ) )
    {
        return nodeTextOf( a, src );
    }
    const bool plain = kindIs( t, "string" ) && ts_node_named_child_count( a ) == 1 && kindIs( ts_node_type( ts_node_named_child( a, 0 ) ), "string_content" );
    return plain ? nodeTextOf( ts_node_named_child( a, 0 ), src ) : std::string_view {};
}

// The value of the `key:` option among a call's arguments, or a null node.
inline TSNode rubyGenOption( TSNode args, std::string_view key, std::string_view src ) noexcept
{
    TSNode      found {};
    ChildCursor cursor( args );
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        if( kindIs( ts_node_type( a ), "pair" ) && rubyPairKeyText( a, src ) == key )
        {
            found = fieldChild( a, NodeField::Value );
            return false;
        }
        return true;
    } );
    return found;
}

// How an enum call names its values' methods (ActiveRecord::Enum): `prefix:` / `suffix:` (or the older `_prefix:` /
// `_suffix:`) — `true` names them after the attribute, a symbol or string after itself — and `scopes: false` /
// `instance_methods: false`, which leave a side out.
struct RubyEnumNaming
{
    std::string prefix;
    std::string suffix;
    bool        scopes    = true;
    bool        instances = true;
};

inline RubyEnumNaming rubyEnumNaming( TSNode args, std::string_view attr, std::string_view src )
{
    const auto option = [ & ]( std::string_view name )
    {
        const TSNode v = rubyGenOption( args, name, src );
        return ts_node_is_null( v ) ? rubyGenOption( args, std::string( "_" ).append( name ), src ) : v;
    };
    const auto affix = [ & ]( std::string_view name ) -> std::string
    {
        const TSNode v = option( name );
        return ts_node_is_null( v ) ? std::string {} : std::string( kindIs( ts_node_type( v ), "true" ) ? attr : rubyGenArgName( v, src ) );
    };
    const auto off = [ & ]( std::string_view name )
    {
        const TSNode v = option( name );
        return !ts_node_is_null( v ) && kindIs( ts_node_type( v ), "false" );
    };
    const std::string prefix = affix( "prefix" );
    const std::string suffix = affix( "suffix" );
    return { prefix.empty() ? prefix : prefix + "_", suffix.empty() ? suffix : "_" + suffix, !off( "scopes" ), !off( "instance_methods" ) };
}

// An enum value's method-friendly label (ActiveRecord::Enum: each run of ASCII non-word characters becomes `_`).
inline std::string rubyEnumLabel( std::string_view value )
{
    std::string out;
    bool        run = false;
    for( const char c : value )
    {
        const auto u    = static_cast<unsigned char>( c );
        const bool word = u >= 0x80 || ( u >= '0' && u <= '9' ) || ( u >= 'A' && u <= 'Z' ) || ( u >= 'a' && u <= 'z' ) || c == '_';
        if( !word && !run )
        {
            out.push_back( '_' );
        }
        run = !word;
        if( word )
        {
            out.push_back( c );
        }
    }
    return out;
}

// The token naming the enum value `v` stands for — a hash's key, an array's element — or a null node. When the values are the
// call's own keywords (`enum :status, trial: 0`), only a pair that is no option names one.
inline TSNode rubyEnumValueToken( TSNode v, bool keywords, std::string_view src ) noexcept
{
    const bool pair   = kindIs( ts_node_type( v ), "pair" );
    const bool option = pair && std::ranges::count( kRubyEnumOptions, rubyPairKeyText( v, src ) ) != 0;
    if( keywords && ( !pair || option ) )
    {
        return {};
    }
    return pair ? fieldChild( v, NodeField::Key ) : v;
}

// An enum value's methods as kRubyGenEnumValue lists them — the instance methods first, then the scopes — less a side the
// call's options leave out.
inline std::span<const RubyGenName> rubyEnumValueMethods( const RubyEnumNaming& naming ) noexcept
{
    static_assert( kRubyGenEnumValue[ 1 ].side == RubyGenSide::Instance && kRubyGenEnumValue[ 2 ].side == RubyGenSide::ClassObject, "instance methods, then scopes" );
    const std::span<const RubyGenName> all( kRubyGenEnumValue );
    return all.subspan( naming.instances ? 0 : 2, ( naming.instances ? 2 : 0 ) + ( naming.scopes ? 2 : 0 ) );
}

// One enum attribute's methods (its reader and writer at `attrToken`) and each of its values' (at the value), named and gated
// by the call's options (rubyEnumNaming). `values` is a hash, an array, or the call's own arguments (rubyEnumValueToken).
inline void rubyGenEnumAttribute( TSNode args, TSNode attrToken, TSNode values, std::string_view src, const RubyGenSink& sink )
{
    const std::string_view attr = rubyGenArgName( attrToken, src );
    if( attr.empty() )
    {
        return;
    }
    sink.from( attr, attrToken, kRubyGenReaderWriter );
    const RubyEnumNaming naming   = rubyEnumNaming( args, attr, src );
    const bool           keywords = ts_node_eq( values, args );
    ChildCursor          cursor( values );
    forEachNamedChild( values, cursor.cur, [ & ]( TSNode v )
    {
        const TSNode           token = rubyEnumValueToken( v, keywords, src );
        const std::string_view value = ts_node_is_null( token ) ? std::string_view {} : rubyGenArgName( token, src );
        if( !value.empty() )
        {
            sink.from( naming.prefix + rubyEnumLabel( value ) + naming.suffix, token, rubyEnumValueMethods( naming ) );
        }
        return true;
    } );
}

// Is `n` an enum's list of values — a hash or an array?
inline bool rubyEnumValues( TSNode n ) noexcept
{
    return !ts_node_is_null( n ) && ( kindIs( ts_node_type( n ), "hash" ) || kindIs( ts_node_type( n ), "array" ) );
}

// What an `enum` call generates: `enum :status, { trial: 0 } | [ :trial ], **options`, `enum :status, trial: 0, …`, or the
// older `enum status: { trial: 0 }, _prefix: true` (several attributes in one call).
inline void rubyGenEnum( TSNode args, std::string_view src, const RubyGenSink& sink )
{
    const TSNode first = rubyFirstNonCommentArg( args );
    if( ts_node_is_null( first ) )
    {
        return;
    }
    if( !kindIs( ts_node_type( first ), "pair" ) )
    {
        const TSNode values = ts_node_next_named_sibling( first );
        rubyGenEnumAttribute( args, first, rubyEnumValues( values ) ? values : args, src, sink );
        return;
    }
    ChildCursor cursor( args );
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode p )
    {
        const TSNode values = kindIs( ts_node_type( p ), "pair" ) ? fieldChild( p, NodeField::Value ) : TSNode {};
        if( rubyEnumValues( values ) && std::ranges::count( kRubyEnumOptions, rubyPairKeyText( p, src ) ) == 0 )
        {
            rubyGenEnumAttribute( args, fieldChild( p, NodeField::Key ), values, src, sink );
        }
        return true;
    } );
}

// The prefix a `delegate` call's `prefix:` gives its names — `true`: the `to:` method's name, `:p`: p — and whether the call
// delegates at all (a call with no `to:`, or `prefix: true` with no method to name it after, raises in ActiveSupport).
inline bool rubyDelegatePrefix( TSNode args, std::string_view src, std::string& prefix )
{
    const TSNode to       = rubyGenOption( args, "to", src );
    const TSNode prefixed = rubyGenOption( args, "prefix", src );
    if( ts_node_is_null( to ) )
    {
        return false;
    }
    const bool             named  = !ts_node_is_null( prefixed ) && kindIs( ts_node_type( prefixed ), "true" );
    const std::string_view source = named ? rubyGenArgName( to, src ) : ts_node_is_null( prefixed ) ? std::string_view {} : rubyGenArgName( prefixed, src );
    if( named && ( source.empty() || !( source.front() == '_' || ( source.front() >= 'a' && source.front() <= 'z' ) ) ) )
    {
        return false;
    }
    prefix = source.empty() ? std::string {} : std::string( source ) + "_";
    return true;
}

// What a `delegate` call generates: each symbol or string argument, prefixed by its `prefix:` (rubyDelegatePrefix).
inline void rubyGenDelegate( TSNode args, std::string_view src, const RubyGenSink& sink )
{
    std::string prefix;
    if( !rubyDelegatePrefix( args, src, prefix ) )
    {
        return;
    }
    const RubyGenName named[] = { { prefix, "", RubyGenSide::Instance } };
    ChildCursor       cursor( args );
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        if( kindIs( ts_node_type( a ), "simple_symbol" ) || kindIs( ts_node_type( a ), "string" ) )
        {
            sink.from( rubyGenArgName( a, src ), a, named );
        }
        return true;
    } );
}

// Is the declaration `n` written where it defines methods (the note above)? `includer` says whether a concern's `included
// do` holds it.
inline bool rubyGenAtDeclarationLevel( TSNode n, bool modelOnly, std::string_view src, bool& includer ) noexcept
{
    includer = rubyInConcernIncludedBlock( n, src );
    if( includer )
    {
        return true;
    }
    if( !rubyAttrAtClassBodyLevel( n, src ) || rubyIsSingletonDef( n ) )
    {
        return false;
    }
    for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( kindIs( ts_node_type( p ), "class" ) || kindIs( ts_node_type( p ), "module" ) )
        {
            return !modelOnly || kindIs( ts_node_type( p ), "class" );
        }
    }
    return false;
}

// What a DSL call's arguments name, by how its verb reads them (RubyGenArgs), onto the sink.
inline void rubyGenFromArguments( const RubyGenVerb& verb, TSNode args, std::string_view src, const RubyGenSink& sink )
{
    if( verb.args == RubyGenArgs::Delegated )
    {
        rubyGenDelegate( args, src, sink );
        return;
    }
    if( verb.args == RubyGenArgs::Enum )
    {
        rubyGenEnum( args, src, sink );
        return;
    }
    if( verb.args == RubyGenArgs::First )
    {
        const TSNode first = rubyFirstNonCommentArg( args );   // a comment before it is no argument
        if( !ts_node_is_null( first ) && !kindIs( ts_node_type( first ), "identifier" ) && !kindIs( ts_node_type( first ), "hash_key_symbol" ) )
        {
            sink.from( rubyGenArgName( first, src ), first, verb.names );
        }
        return;
    }
    ChildCursor cursor( args );
    forEachNamedChild( args, cursor.cur, [ & ]( TSNode a )
    {
        if( kindIs( ts_node_type( a ), "simple_symbol" ) )
        {
            sink.from( rubyGenArgName( a, src ), a, verb.names );
        }
        return true;
    } );
}

// The methods the declaration `n` generates — a DSL call (kRubyGeneratedVerbs) or an `alias new old` — onto `out` (cleared
// first); none where it is not written at declaration level.
inline void rubyGeneratedMethods( TSNode n, std::string_view src, std::vector<RubyGenMethod>& out )
{
    out.clear();
    RubyGenSink sink { out };
    if( kindIs( ts_node_type( n ), "alias" ) )
    {
        const TSNode name = fieldChild( n, NodeField::Name );
        if( !ts_node_is_null( name ) && rubyGenAtDeclarationLevel( n, false, src, sink.includer ) )
        {
            sink.from( rubyGenArgName( name, src ), name, kRubyGenMethod );
        }
        return;
    }
    const bool         bare = ts_node_is_null( fieldChild( n, NodeField::Receiver ) );
    const RubyGenVerb* verb = bare ? findByField( kRubyGeneratedVerbs, &RubyGenVerb::verb, fieldIdentifierText( n, NodeField::Method, src ) ) : nullptr;
    const TSNode       args = fieldChild( n, NodeField::Arguments );
    if( verb != nullptr && !ts_node_is_null( args ) && rubyGenAtDeclarationLevel( n, verb->modelOnly, src, sink.includer ) )
    {
        rubyGenFromArguments( *verb, args, src, sink );
    }
}

// Could the file declare a generated method at all — does it spell `alias` or any verb?
inline bool rubyMayGenerate( std::string_view src ) noexcept
{
    if( src.find( "alias" ) != std::string_view::npos )
    {
        return true;   // `alias` and `alias_method`
    }
    for( const RubyGenVerb& v : kRubyGeneratedVerbs )
    {
        if( src.find( v.verb ) != std::string_view::npos )
        {
            return true;
        }
    }
    return false;
}

// Each declaration in the file, with the methods it generates (rubyGeneratedMethods): `visit( declaration, methods )`. A def
// body declares nothing, so the walk does not enter one; nor a declaration, once read.
template<class Visit>
inline void forEachRubyGenerated( TSNode root, std::string_view src, Visit&& visit )
{
    if( !rubyMayGenerate( src ) )
    {
        return;
    }
    std::vector<RubyGenMethod> methods;
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            return true;
        }
        if( !kindIs( t, "call" ) && !kindIs( t, "alias" ) )
        {
            return false;
        }
        rubyGeneratedMethods( n, src, methods );
        if( methods.empty() )
        {
            return false;
        }
        visit( n, methods );
        return true;
    } );
}

// The generated methods as Section definitions of the class or concern around each declaration (the note above).
inline void captureRubyGeneratedDefs( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawDef>& defs )
{
    forEachRubyGenerated( root, src, [ & ]( TSNode decl, const std::vector<RubyGenMethod>& methods )
    {
        const std::uint32_t start = ts_node_start_byte( decl );
        const std::uint32_t end   = ts_node_end_byte( decl );
        for( std::size_t k = 0; k < methods.size() && start + k < end; ++k )
        {
            const RubyGenMethod& m = methods[ k ];
            RawDef               d;
            d.fileId = fileId; d.line = ts_node_start_point( m.token ).row + 1; d.startByte = ts_node_start_byte( m.token ); d.endByte = ts_node_end_byte( m.token );
            d.nameByte = start + std::uint32_t( k ); d.loc = 1; d.kind = SymKind::Section; d.lang = Lang::Ruby;
            d.scope = rubyEnclosingScopeOf( m.token, src ); d.name = m.name;
            if( !d.scope.empty() )
            {
                defs.push_back( std::move( d ) );
            }
        }
    } );
}

// The class methods among them, each a RubySingletonDef binding named for it at its definition's start (a concern's carry
// kRubyIncluderMark: each includer's) — the join src/ruby_generated.h buildRubyGenerated reads.
inline void captureRubyGeneratedSides( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    forEachRubyGenerated( root, src, [ & ]( TSNode decl, const std::vector<RubyGenMethod>& methods )
    {
        const std::uint32_t span = ts_node_end_byte( decl ) - ts_node_start_byte( decl );
        for( std::size_t k = 0; k < methods.size() && k < span; ++k )
        {
            const RubyGenMethod& m = methods[ k ];
            if( m.side == RubyGenSide::ClassObject )
            {
                binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( m.token ), .lang = Lang::Ruby, .kind = LocalBindKind::RubySingletonDef,
                                           .var = m.name, .importedName = m.includer ? std::string( kRubyIncluderMark ) : std::string {} } );
            }
        }
    } );
}

// ─── A model's table (parser version 279, test/rubycolumncheck.sh; src/ruby_generated.h) ────────────────────────────────────
// Which columns a model's instances read is a fact of two files: a rendered db/schema.rb says which columns each table has,
// and the class body which table it reads (`self.table_name = "x"`; else Rails' name for the class, src/ruby_generated.h).
// Each is a LocalBindKind::RubyTable binding, joined over the tree by src/ruby_generated.h buildRubyGenerated: a table at
// its create_table call's bytes, which hold its columns' definitions (the schema capture above), and a class body's
// `self.table_name =` at its own start, marked kRubyModelTableMark. Only a name written as a string or a symbol is read.

// The table a class body names at its level — `self.table_name = "x"` or `= :x` — or empty.
inline std::string rubyModelTableName( TSNode n, std::string_view src )
{
    const TSNode left  = fieldChild( n, NodeField::Left );
    const TSNode right = fieldChild( n, NodeField::Right );
    if( ts_node_is_null( left ) || ts_node_is_null( right ) || !kindIs( ts_node_type( left ), "call" )
        || fieldIdentifierText( left, NodeField::Method, src ) != "table_name" )
    {
        return {};
    }
    const TSNode recv = fieldChild( left, NodeField::Receiver );
    bool         includer = false;
    if( ts_node_is_null( recv ) || !kindIs( ts_node_type( recv ), "self" ) || !rubyGenAtDeclarationLevel( n, /*modelOnly=*/true, src, includer ) || includer )
    {
        return {};
    }
    const bool literal = kindIs( ts_node_type( right ), "string" ) || kindIs( ts_node_type( right ), "simple_symbol" );
    return literal ? std::string( rubyGenArgName( right, src ) ) : std::string {};   // a plain string or a symbol, not an expression
}

// One file's tables and table names, into `binds` — a file that spells neither `create_table` nor `table_name` is not walked.
// A def body declares neither, so the walk does not enter one.
inline void captureRubyTables( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "create_table" ) == std::string_view::npos && src.find( "table_name" ) == std::string_view::npos )
    {
        return;
    }
    rubyWalkUntaken( root, [ & ]( TSNode n )
    {
        const char* t = ts_node_type( n );
        if( kindIs( t, "method" ) || kindIs( t, "singleton_method" ) )
        {
            return true;
        }
        if( kindIs( t, "assignment" ) )
        {
            if( std::string name = rubyModelTableName( n, src ); !name.empty() )
            {
                binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( n ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyTable,
                                           .var = std::move( name ), .importedName = std::string( kRubyModelTableMark ) } );
            }
            return true;
        }
        if( !kindIs( t, "call" ) || fieldIdentifierText( n, NodeField::Method, src ) != "create_table" )
        {
            return false;
        }
        const RubySchemaTable table = rubySchemaTableOf( n, src );
        std::string           name  = ts_node_is_null( table.name ) ? std::string {} : stringLiteralText( table.name, src );
        if( !name.empty() )
        {
            binds.push_back( RawBind { .fileId = fileId, .startByte = ts_node_start_byte( n ), .lang = Lang::Ruby, .kind = LocalBindKind::RubyTable,
                                       .spanStart = ts_node_start_byte( n ), .spanEnd = ts_node_end_byte( n ), .var = std::move( name ) } );
        }
        return true;
    } );
}

// ─── FactoryBot's factory definitions (parser version 132, test/rubytypedrecvcheck.sh) ─────────────────────────────────
// `factory :user do … end` inside a `FactoryBot.define` (or `FactoryGirl.define`) block defines what `create( :user )`
// builds, and its class is FactoryBot's own rule: the `class:` option as written — a constant, or a string naming one (its
// final segment) — else the enclosing factory's (a nested factory builds its parent's class), else the `parent:` factory's
// when the file defined it above, else the name camelised (`:user_profile` → UserProfile). One RubyFactory binding per name
// and per `aliases:` entry; graph.h rubyFactoryClasses joins them over the tree, where two classes for one name type nothing.
// A `class:` of any other spelling (a symbol, an expression) records no factory: its class is not known.

// `user_profile` → UserProfile, `admin/user` → User: the final segment of the constant FactoryBot camelises the name into
inline std::string rubyFactoryDefaultClass( std::string_view name )
{
    const std::size_t slash = name.rfind( '/' );
    std::string       out;
    bool              upper = true;
    for( const char c : name.substr( slash == std::string_view::npos ? 0 : slash + 1 ) )
    {
        if( c == '_' )
        {
            upper = true;
            continue;
        }
        out.push_back( upper && c >= 'a' && c <= 'z' ? char( c - 'a' + 'A' ) : c );
        upper = false;
    }
    return out;
}

// The value of the `key:` option among a call's arguments (`class: "User"`, `parent: :user`), or null.
inline TSNode rubyCallOption( TSNode call, std::string_view key, std::string_view src )
{
    const TSNode args = fieldChild( call, NodeField::Arguments );
    TSNode       value {};
    if( !ts_node_is_null( args ) )
    {
        ChildCursor cursor( args );
        forEachNamedChild( args, cursor.cur, [ & ]( TSNode c )
        {
            const TSNode k     = kindIs( ts_node_type( c ), "pair" ) ? fieldChild( c, NodeField::Key ) : TSNode {};
            const bool   named = !ts_node_is_null( k ) && kindIs( ts_node_type( k ), "hash_key_symbol" ) && pattern::nodeText( k, src ) == key;
            value              = named ? fieldChild( c, NodeField::Value ) : value;
            return !named;
        } );
    }
    return value;
}

// The class a `class:` option names: a constant's final segment, or a plain string's (`"Admin::User"` → User); else empty.
inline std::string_view rubyFactoryClassOption( TSNode value, std::string_view src )
{
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    if( isRubyConstantNode( value ) )
    {
        return rubyFinalConstant( value, src );
    }
    if( !kindIs( ts_node_type( value ), "string" ) || ts_node_named_child_count( value ) != 1
        || !kindIs( ts_node_type( ts_node_named_child( value, 0 ) ), "string_content" ) )
    {
        return {};
    }
    const std::string_view text = pattern::nodeText( ts_node_named_child( value, 0 ), src );
    const std::size_t      cut  = text.rfind( "::" );
    return cut == std::string_view::npos ? text : text.substr( cut + 2 );
}

class RubyFactoryWalk
{
public:
    RubyFactoryWalk( std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds ) : fileId_( fileId ), src_( src ), binds_( binds ) {}
    void run( TSNode root );

private:
    struct Item
    {
        TSNode        node;
        bool          inDefine;   // inside a `FactoryBot.define` block
        std::uint32_t parent;     // index into classes_ of the enclosing factory's class; kNone outside one
    };
    static constexpr std::uint32_t kNone = 0xFFFFFFFFu;
    void define( TSNode call, const Item& item );
    std::string classOf( TSNode call, std::string_view name, const Item& item ) const;
    void emit( TSNode call, std::string_view name, const std::string& cls );

    std::uint32_t                    fileId_;
    std::string_view                 src_;
    std::vector<RawBind>&            binds_;
    std::vector<Item>                stack_;
    std::vector<TSNode>              kids_;
    std::vector<std::string>         classes_;
    HashMap<std::string_view, std::uint32_t> byName_;   // a factory defined above in this file → its class
};

inline void RubyFactoryWalk::run( TSNode root )
{
    ChildCursor cursor( root );
    stack_.push_back( Item { root, false, kNone } );
    while( !stack_.empty() )
    {
        Item item = stack_.back();
        stack_.pop_back();
        const TSNode n = item.node;
        if( kindIs( ts_node_type( n ), "call" ) )
        {
            const TSNode           recv = fieldChild( n, NodeField::Receiver );
            const std::string_view on   = !ts_node_is_null( recv ) && isRubyConstantNode( recv ) ? rubyFinalConstant( recv, src_ ) : std::string_view {};
            const std::string_view m    = fieldChildTextOfKind( n, NodeField::Method, "identifier", src_ );
            item.inDefine = item.inDefine || ( ( on == "FactoryBot" || on == "FactoryGirl" ) && m == "define" );
            if( item.inDefine && ts_node_is_null( recv ) && m == "factory" )
            {
                define( n, item );
                continue;
            }
        }
        collectChildren( n, cursor.cur, kids_ );
        for( std::size_t i = kids_.size(); i > 0; --i )
        {
            stack_.push_back( Item { kids_[ i - 1 ], item.inDefine, item.parent } );
        }
    }
}

// one `factory :name, …` call: its class (the section note above), a binding per name and alias, then its block's
// factories, which build this class unless they say otherwise
inline void RubyFactoryWalk::define( TSNode call, const Item& item )
{
    const std::string_view name = rubyFirstSymbolArgument( call, src_ );
    std::string            cls  = name.empty() ? std::string {} : classOf( call, name, item );
    if( cls.empty() )
    {
        return;   // no symbol name, or a class this file does not say: no factory is recorded, and none nested in it
    }
    const std::uint32_t index = std::uint32_t( classes_.size() );
    classes_.push_back( std::move( cls ) );
    byName_.try_emplace( name, index );
    emit( call, name, classes_[ index ] );
    if( const TSNode aliases = rubyCallOption( call, "aliases", src_ ); !ts_node_is_null( aliases ) && kindIs( ts_node_type( aliases ), "array" ) )
    {
        ChildCursor cursor( aliases );
        forEachNamedChild( aliases, cursor.cur, [ & ]( TSNode a )
        {
            const std::string_view alias = kindIs( ts_node_type( a ), "simple_symbol" ) ? pattern::nodeText( a, src_ ).substr( 1 ) : std::string_view {};
            if( !alias.empty() )
            {
                emit( call, alias, classes_[ index ] );
            }
            return true;
        } );
    }
    if( const TSNode block = rubyCallBlock( call ); !ts_node_is_null( block ) )
    {
        stack_.push_back( Item { block, true, index } );
    }
}

// the class `factory :name, …` builds, by FactoryBot's rule (the section note above); empty when this file does not say
inline std::string RubyFactoryWalk::classOf( TSNode call, std::string_view name, const Item& item ) const
{
    if( const TSNode opt = rubyCallOption( call, "class", src_ ); !ts_node_is_null( opt ) )
    {
        return std::string( rubyFactoryClassOption( opt, src_ ) );
    }
    if( const TSNode parent = rubyCallOption( call, "parent", src_ ); !ts_node_is_null( parent ) )
    {
        const bool symbol = kindIs( ts_node_type( parent ), "simple_symbol" );
        const auto named  = symbol ? byName_.find( pattern::nodeText( parent, src_ ).substr( 1 ) ) : byName_.end();
        return named == byName_.end() ? std::string {} : classes_[ named->second ];
    }
    return item.parent != kNone ? classes_[ item.parent ] : rubyFactoryDefaultClass( name );
}

inline void RubyFactoryWalk::emit( TSNode call, std::string_view name, const std::string& cls )
{
    RawBind b;
    b.fileId    = fileId_;
    b.startByte = ts_node_start_byte( call );
    b.lang      = Lang::Ruby;
    b.kind      = LocalBindKind::RubyFactory;
    b.var       = std::string( name );
    b.typeName  = cls;
    binds_.push_back( std::move( b ) );
}

// One file's FactoryBot factories, into `binds` — a file with no `FactoryBot.define` / `FactoryGirl.define` is not walked.
inline void captureRubyFactories( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawBind>& binds )
{
    if( src.find( "FactoryBot.define" ) != std::string_view::npos || src.find( "FactoryGirl.define" ) != std::string_view::npos )
    {
        RubyFactoryWalk( fileId, src, binds ).run( root );
    }
}

// The Ruby mixin directive a @reference.mixin capture names (family 4, slice 4a): when `call` is a receiverless
// `include`/`extend`/`prepend` at class-DSL position, its constant argument is an ANCESTOR of the enclosing class, so
// it emits one inherit reference through the shared emitBaseRef — the shape a superclass mints. Both guards are here
// because a tags pattern can state neither: the TEXT (tags predicates do not run, so `Logger.new( Config )` matches the
// same call shape) and the POSITION (a method body, another block and the file top level emit nothing).
//
// This is RUBY's reader and lives in the Ruby lane for that reason. `@reference.mixin` is a language-neutral capture
// name, so the shared consumer reaches it with no Lang:: test; the language therefore arrives FROM the call site and is
// asserted here. Ruby is the only emitter of `@reference.mixin` today. A second language that adopts the capture must
// NOT reuse this function — its guards are Ruby's fields and Ruby's directive names, and it mints Lang::Ruby refs, so a
// non-Ruby call would be silently dropped — it must add its own emitCaptured<Lang>MixinBase and a per-language dispatch
// at the consumer arm (PHP's in-body `use Trait;`, near captureBases' header, is the documented sibling).
//
// The one construction where this path is NOT byte-identical to the walk it replaced (the maintainer's #401 note, and
// pathological): the Include record still comes from the captureIncludes walk, which stops at kMaxImportContainerDepth
// (256 AST levels), while this inherit reference comes from the query, which has no such bound. Past that depth — 260
// nested `module`s with an `include M` innermost — rubyDirectiveSitesByFile finds no directive for the reference, so
// --lego lists the includer as an implementor while the walk's own depth-bound notice on stderr ("import-container
// nesting past the depth bound — deeper imports not captured") stays the only degraded line: no ruby_bases_unscoped=
// appears on any verb. No real code reaches 256 levels of nesting; the cut is stated here so "byte-identical" reads exactly.
inline void emitCapturedRubyMixinBase( TSNode call, TSNode constant, std::uint32_t fileId, Lang lang, std::string_view src,
                                       std::vector<RawRef>& refs )
{
    EXPECTS( lang == Lang::Ruby );   // the only emitter of @reference.mixin; see the note above
    if( rubyNamedDirective( call, src, kRubyMixinDirectives ).empty()
        || !( rubyAttrAtClassBodyLevel( call, src ) || rubyInConcernIncludedBlock( call, src ) ) )
    {
        return;
    }
    emitBaseRef( constant, fileId, lang, src, refs );
}

} // namespace - ingest_ruby.h section of ingest.cpp

} // namespace rw
