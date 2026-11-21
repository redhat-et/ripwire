#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_rustmacroargs.h is a section of ingest.cpp; include it only there"
#endif
// ingest_rustmacroargs.h — RUST-MACRO-ARGS: the calls written inside a macro invocation's arguments.
// Gate: test/rustmacropathcheck.sh, the A arms (fixture test/rustmacropathfix/args).
//
// WHAT WAS MISSING. tree-sitter-rust reads the arguments of `name!( … )` as one opaque `token_tree`: a macro decides
// what its tokens mean, so the grammar parses none of them. The tags query therefore saw the macro and nothing inside
// it. Every call written in `assert_eq!( f(), 1 )`, `format!( "{}", g() )`, `write!( out, "{}", x.name() )` or a user
// macro's block arm (`tap_inner!( self, mut this => { this.inner.route( path ) } )`) had no reference: tests reached
// nothing through their asserts, and a method whose body is one macro had no callees.
//
// THE RE-READ (per file, pure, deterministic). After the tags pass, each macro invocation it recorded is revisited:
//   (1) its token tree, delimiters included, is parsed AS WRITTEN as one Rust statement: `( a, b )` is a tuple or a
//       parenthesized expression, `[ a, b ]` and `[ x; n ]` an array, `{ … }` a block;
//   (2) the calls are kept only when that parse holds NO error and NO missing token and is exactly that one expression.
//       The same tags query then runs over the fragment, so a call inside an argument carries the receiver, qualifier
//       and arity facts of a call written anywhere else, at its real byte and line;
//   (3) a macro invocation found inside an accepted fragment is revisited the same way (`assert!( matches!( f(), P ) )`);
//   (4) a token tree that is NOT one expression (a pattern, a `=>` arm, a DSL) emits nothing itself. Two kinds of its
//       direct pieces are tried, each by rule (1)-(2): an ARM BODY, the tokens after a top-level `=>` up to the next
//       top-level `,` or `;` (Rust's own match-arm spelling: `map_inner!( self, this => Inner { a: this.a.f() } )`,
//       `hashmap!{ "k" => make( 1 ) }`), read as one expression; and a `{ … }` group, read as a block (a macro arm's
//       body: `tap_inner!( self, mut this => { … } )`). The tokens around them (the arm's pattern, a DSL's words) are
//       never read: a list is not split at its commas, so one call-shaped word inside a DSL sentence emits nothing.
//
// WHAT IS NEVER READ. A `macro_rules!` definition (a `macro_definition` node, never an invocation: its `$x:expr`
// metavariables and transcriber are not calls of the enclosing code). The token-quoting macros (kTokenQuotingMacros):
// their arguments are code as DATA. `cfg!`, whose `any( … )` / `all( … )` / `not( … )` are predicates spelled like
// calls. For the pattern macros (kPatternArgMacros) only the first argument is an expression; the pattern after it
// (`Some( x )`, `Foo::Bar( _ )`) is spelled like a call and is not one.
//
// A MATCHER'S LITERAL WORDS ARE NOT CALLS (test/rustmacrocallcheck.sh [N] matcher_fn, [K1]). A `macro_rules!` matcher may spell
// a word as a literal token: `( matcher_fn ( $x:expr ), $f:ident ) => …` matches `wrap!( matcher_fn( 3 ), drop )`, whose tokens
// parse clean as a tuple holding the call `matcher_fn( 3 )`. That word is consumed by the matcher, never called. So when the
// invoked macro is a `macro_rules!` THIS FILE defines, a bare call (no qualifier, no receiver) whose name one of its matchers
// spells as a literal word before a `( … )` group is dropped from that invocation's own fragment (a nested invocation of
// another macro reads its own matchers). Scope, stated: the matchers are read from this file's own definitions only — the
// re-read is a per-file pass (one parse worker, no other file's tree), and a re-read reference does not record its
// invocation, so a macro defined in another file (a `#[macro_use] mod` sibling, an exported macro) is not consulted and its
// literal words stay calls. The cost of the rule is the opposite miss: an `$x:expr` argument that calls a function spelled
// like one of the macro's literal words is not read either.
//
// HONESTY. A re-read reference is an ordinary Call or Macro reference: the resolver proves it, declines it or binds it
// by name exactly as it would outside a macro. No definition, binding or import is taken from a fragment, so a `let`
// inside a macro block types no receiver and such a call stays declined rather than guessed. A macro can do anything
// with its tokens, which is why rule (2) demands a whole clean parse before a single call is believed.
//
// COST. Only a token tree that holds a `(` is parsed (no call can be written without one). The fragment parse reads
// the source bytes in place through an included range: no copy of the file is made. A parse whose every branch holds
// an error is cancelled (macroArgParseIsHopeless), so tokens that are not Rust are not error-recovered. Nesting past kMacroArgNestingDepth
// is not followed and the file is disclosed extract-partial.

namespace rw
{
namespace
{

// How deep a re-read follows macro invocations inside macro arguments, and `{ … }` groups inside a rejected token tree.
// Each level parses a strict sub-range of the one above it, so the work on a file is at most this many times its bytes.
constexpr std::uint32_t kMacroArgNestingDepth = 16;

enum class MacroArgPolicy : std::uint8_t
{
    Whole,           // the token tree is tried as one expression
    FirstArgument,   // only the tokens before the first top-level comma are (the rest is a pattern)
    Never,           // the arguments are not code of the enclosing function
};

// Arguments are code as data: tokens to paste into another program, or to print.
inline constexpr std::array<std::string_view, 6> kTokenQuotingMacros = { "quote", "quote_spanned", "parse_quote", "parse_quote_spanned", "stringify",
                                                                         "concat_idents" };
// `cfg!( any( unix, feature = "x" ) )`: configuration predicates, spelled like calls.
inline constexpr std::array<std::string_view, 1> kPredicateMacros = { "cfg" };
// `matches!( expr, pattern )`: one expression, then a pattern (and an optional guard).
inline constexpr std::array<std::string_view, 3> kPatternArgMacros = { "matches", "assert_matches", "debug_assert_matches" };

inline MacroArgPolicy macroArgPolicy( std::string_view macroName ) noexcept
{
    const auto names = [ macroName ]( const auto& table ) { return std::find( table.begin(), table.end(), macroName ) != table.end(); };
    if( names( kTokenQuotingMacros ) || names( kPredicateMacros ) )
    {
        return MacroArgPolicy::Never;
    }
    return names( kPatternArgMacros ) ? MacroArgPolicy::FirstArgument : MacroArgPolicy::Whole;
}

// One macro invocation the tags pass recorded: where its node starts, and what its name allows.
struct MacroArgSite
{
    std::uint32_t  startByte = 0;
    MacroArgPolicy policy    = MacroArgPolicy::Whole;
};

// The bytes one fragment parse reads: [startByte, endByte) of the source, then one `;` that is not in the source.
struct MacroArgSpan
{
    std::uint32_t startByte = 0;
    std::uint32_t endByte   = 0;
    TSPoint       startPoint{};
    TSPoint       endPoint{};
};

enum class MacroArgShape : std::uint8_t
{
    DelimitedGroup,   // a whole token tree with its delimiters: must read as a tuple, parenthesized, array, unit or block expression
    Expression,       // one argument: any one expression
};

// Per-worker scratch, reused across files: the fragment parser (its included range never touches the worker's own
// parser) and the rows a fragment's tags pass writes that the re-read does not keep.
struct MacroArgScratch
{
    ParserGuard          parser;
    std::vector<RawDef>  defs;
    std::vector<RawBind> binds;
    std::vector<Include> includes;
};

// A `macro_rules!` this file defines: its name, and the words its matchers spell as literal tokens before a `( … )` group
// (views into the file's bytes and its definition rows, both alive for the whole pass).
struct MacroMatcherWords
{
    std::string_view              name;
    std::vector<std::string_view> words;
};

// One file's re-read.
struct MacroArgPass
{
    MacroArgScratch&     work;
    TSQueryCursor*       cursor;
    const LangEntry&     le;
    std::uint32_t        fileId;
    std::string_view     src;
    std::vector<RawRef>& refs;
    ExtractShortfall&    shortfall;
    std::span<const MacroMatcherWords>        matchers{};       // this file's `macro_rules!` matcher words (fileMacroMatcherWords)
    std::span<const std::string_view>         matcherWords{};   // the invocation being re-read: its macro's literal call-shaped words
};

// The fragment's document: the source up to `endByte`, where the statement's `;` stands in for whatever the source
// holds there (the argument's comma, or the byte after the closing delimiter), and nothing after it.
struct MacroArgInput
{
    std::string_view src;
    std::uint32_t    endByte = 0;
};

inline const char* readMacroArgBytes( void* payload, std::uint32_t byteIndex, TSPoint, std::uint32_t* bytesRead )
{
    const MacroArgInput& input = *static_cast<const MacroArgInput*>( payload );
    if( byteIndex < input.endByte )
    {
        *bytesRead = input.endByte - byteIndex;
        return input.src.data() + byteIndex;
    }
    *bytesRead = byteIndex == input.endByte ? 1u : 0u;
    return ";";
}

// The parser reports, every hundred steps or so, whether EVERY parse it still follows holds an error. From there the
// tree can only be one rule (2) rejects, so the parse is cancelled: a DSL body costs its first few tokens, not the
// error recovery of all of it.
inline bool macroArgParseIsHopeless( TSParseState* state )
{
    return state->has_error;
}

// Null when the fragment cannot be code (cancelled as hopeless) or the range is refused.
inline TSTree* parseMacroArgFragment( TSParser* parser, std::string_view src, const MacroArgSpan& span )
{
    const TSRange range{ span.startPoint, TSPoint{ span.endPoint.row, span.endPoint.column + 1u }, span.startByte, span.endByte + 1u };
    if( !ts_parser_set_included_ranges( parser, &range, 1 ) )
    {
        return nullptr;
    }
    MacroArgInput payload{ src, span.endByte };
    TSInput       input{};
    input.payload  = &payload;
    input.read     = readMacroArgBytes;
    input.encoding = TSInputEncodingUTF8;
    TSParseOptions options{};
    options.progress_callback = macroArgParseIsHopeless;
    TSTree* tree = ts_parser_parse_with_options( parser, nullptr, input, options );
    if( tree == nullptr )
    {
        ts_parser_reset( parser );   // a cancelled parse would otherwise RESUME on the next call
    }
    return tree;
}

// Rule (2): the fragment is exactly one clean expression statement that starts where the span starts.
inline bool macroArgFragmentIsCode( TSNode root, const MacroArgSpan& span, MacroArgShape shape )
{
    if( ts_node_has_error( root ) )   // an ERROR or a MISSING token anywhere
    {
        return false;
    }
    const std::uint32_t statements = ts_node_named_child_count( root );
    if( statements == 0 || statements > 2 )
    {
        return false;
    }
    const TSNode statement = ts_node_named_child( root, 0 );
    if( !kindIs( ts_node_type( statement ), "expression_statement" ) || ts_node_start_byte( statement ) != span.startByte )
    {
        return false;
    }
    if( statements == 2 && !kindIs( ts_node_type( ts_node_named_child( root, 1 ) ), "empty_statement" ) )   // `{ … }` then the `;`
    {
        return false;
    }
    if( shape == MacroArgShape::Expression )
    {
        return true;
    }
    static constexpr std::array<std::string_view, 5> kGroupKinds = { "tuple_expression", "parenthesized_expression", "array_expression", "unit_expression",
                                                                     "block" };
    const TSNode           expression = ts_node_named_child( statement, 0 );
    const std::string_view kind       = ts_node_is_null( expression ) ? std::string_view{} : std::string_view( ts_node_type( expression ) );
    return std::find( kGroupKinds.begin(), kGroupKinds.end(), kind ) != kGroupKinds.end();
}

// A fragment that declares a type makes the tags pass's definition arm mint relation rows (a base, a member's type).
// They belong to a definition the re-read does not keep. Every other row a Rust fragment yields is a call or a macro.
inline bool isRelationRow( const RawRef& r ) noexcept
{
    return r.isInherit || r.isCompose;
}

// A bare call the invoked macro's matcher spells as a literal word: the matcher consumes the word, nothing calls it.
inline bool isMatcherLiteralCall( const RawRef& r, std::span<const std::string_view> matcherWords ) noexcept
{
    return r.role == RefRole::Call && !r.memberCall && r.qualifier.empty() && std::ranges::contains( matcherWords, std::string_view( r.name ) );
}

// The words one matcher token tree [begin, end) spells as literal tokens right before a `( … )` group. A metavariable
// (`$x`), a fragment specifier or path segment after `:`, a number and anything in a literal or comment is not one.
inline void appendMatcherLiteralCallWords( std::string_view src, std::uint32_t begin, std::uint32_t end, std::vector<std::string_view>& words )
{
    using namespace rust_transcriber_scan;
    std::uint32_t line = 0;   // skipLiteralOrComment counts newlines; no line is read here
    std::uint32_t at   = begin;
    while( at < end )
    {
        if( skipLiteralOrComment( src, at, end, line ) )
        {
            continue;
        }
        if( !namesplit::isIdentChar( src[ at ] ) || ( at > begin && namesplit::isIdentChar( src[ at - 1 ] ) ) )
        {
            ++at;
            continue;
        }
        std::uint32_t wordEnd = at;
        while( wordEnd < end && namesplit::isIdentChar( src[ wordEnd ] ) )
        {
            ++wordEnd;
        }
        std::uint32_t before = 0;
        const char    prev   = prevNonBlank( src, begin, at, before );
        const auto    next   = skipBlanks( src, wordEnd, end );
        const bool    digit  = src[ at ] >= '0' && src[ at ] <= '9';
        if( !digit && prev != '$' && prev != ':' && next < end && src[ next ] == '(' )
        {
            words.push_back( src.substr( at, wordEnd - at ) );
        }
        at = wordEnd;
    }
}

// Each rule's matcher (`macro_rule`'s left:) of `macroDef`: its literal call-shaped words.
inline void appendMacroMatcherWords( TSNode macroDef, std::string_view src, std::vector<std::string_view>& words )
{
    ChildCursor cursor( macroDef );
    forEachChild( macroDef, cursor.cur, [ & ]( TSNode rule )
    {
        const TSNode left = kindIs( ts_node_type( rule ), "macro_rule" ) ? fieldChild( rule, NodeField::Left ) : TSNode{};
        if( !ts_node_is_null( left ) && ts_node_end_byte( left ) <= src.size() )
        {
            appendMatcherLiteralCallWords( src, ts_node_start_byte( left ), ts_node_end_byte( left ), words );
        }
        return true;
    } );
}

// This file's `macro_rules!` definitions (its Macro rows `defs`, each spanning exactly its `macro_definition` node) and the
// literal call-shaped words each one's matchers spell. A definition whose matchers spell none is left out.
inline std::vector<MacroMatcherWords> fileMacroMatcherWords( TSNode root, std::string_view src, std::span<const RawDef> defs )
{
    std::vector<MacroMatcherWords> matchers;
    for( const RawDef& def : defs )
    {
        const TSNode node = def.kind == SymKind::Macro ? ts_node_descendant_for_byte_range( root, def.startByte, def.endByte ) : TSNode{};
        if( ts_node_is_null( node ) || !kindIs( ts_node_type( node ), "macro_definition" ) )
        {
            continue;
        }
        MacroMatcherWords entry{ def.name, {} };
        appendMacroMatcherWords( node, src, entry.words );
        if( !entry.words.empty() )
        {
            matchers.push_back( std::move( entry ) );
        }
    }
    return matchers;
}

// The literal call-shaped words of the macro an invocation names (its last path segment: `wrap` in `crate::wrap!( … )`)
// among this file's definitions; empty when the file defines none. A name defined twice (a fn-local macro beside a module
// one) reads the first definition's words: which scope wins at the invocation is not resolved here.
inline std::span<const std::string_view> invokedMacroMatcherWords( std::span<const MacroMatcherWords> matchers, TSNode invocation,
                                                                   std::string_view src ) noexcept
{
    TSNode path = ts_node_named_child( invocation, 0 );
    if( !ts_node_is_null( path ) && kindIs( ts_node_type( path ), "scoped_identifier" ) )
    {
        path = fieldChild( path, NodeField::Name );
    }
    const std::string_view name = ts_node_is_null( path ) ? std::string_view{} : nodeTextOf( path, src );
    for( const MacroMatcherWords& macro : matchers )
    {
        if( !name.empty() && macro.name == name )
        {
            return macro.words;
        }
    }
    return {};
}

// The macro invocations among refs[ first, end ), ordered by position. A `Never` macro is not a site at all.
inline std::vector<MacroArgSite> macroArgSitesIn( const std::vector<RawRef>& refs, std::size_t first )
{
    std::vector<MacroArgSite> sites;
    for( std::size_t index = first; index < refs.size(); ++index )
    {
        const RawRef& r = refs[ index ];
        if( r.role != RefRole::Macro )
        {
            continue;
        }
        const MacroArgPolicy policy = macroArgPolicy( std::string_view( r.name ) );
        if( policy != MacroArgPolicy::Never )
        {
            sites.push_back( { r.startByte, policy } );
        }
    }
    std::sort( sites.begin(), sites.end(), []( const MacroArgSite& a, const MacroArgSite& b ) { return a.startByte < b.startByte; } );
    return sites;
}

// Leave the current node's subtree: the next node in document order that is not inside it. False at the end of the tree.
inline bool gotoNextOutsideSubtree( TSTreeCursor& cur ) noexcept
{
    while( !ts_tree_cursor_goto_next_sibling( &cur ) )
    {
        if( !ts_tree_cursor_goto_parent( &cur ) )
        {
            return false;
        }
    }
    return true;
}

// Visit the `macro_invocation` node that starts at each site, in order. One forward walk: a subtree that ends before
// the next site is skipped whole, so the cost follows the paths to the sites, not the size of the tree.
template<class Visit>
inline void forEachMacroInvocationAt( TSNode root, const std::vector<MacroArgSite>& sites, const Visit& visit )
{
    ChildCursor   cursor( root );
    TSTreeCursor& cur  = cursor.cur;
    std::size_t   next = 0;
    bool          more = true;
    while( more && next < sites.size() )
    {
        const TSNode        node = ts_tree_cursor_current_node( &cur );
        const std::uint32_t want = sites[ next ].startByte;
        const std::uint32_t at   = ts_node_start_byte( node );
        if( at > want )
        {
            ++next;   // every node that could hold this site has been entered: no invocation node starts there
        }
        else if( at == want && kindIs( ts_node_type( node ), "macro_invocation" ) )
        {
            visit( node, sites[ next ] );
            ++next;
        }
        else if( ts_node_end_byte( node ) <= want || !ts_tree_cursor_goto_first_child( &cur ) )
        {
            more = gotoNextOutsideSubtree( cur );
        }
    }
}

inline MacroArgSpan macroArgSpanOf( TSNode tokenTree ) noexcept
{
    return { ts_node_start_byte( tokenTree ), ts_node_end_byte( tokenTree ), ts_node_start_point( tokenTree ), ts_node_end_point( tokenTree ) };
}

// No call is written without a `(` after the opening delimiter.
inline bool macroArgHoldsCallShape( std::string_view src, const MacroArgSpan& span ) noexcept
{
    if( span.endByte > src.size() || span.endByte < span.startByte + 2u )
    {
        return false;
    }
    return src.substr( span.startByte + 1u, span.endByte - span.startByte - 2u ).find( '(' ) != std::string_view::npos;
}

inline void discloseMacroArgNesting( MacroArgPass& pass )
{
    DISCLOSE( pass.shortfall, ExtractShortfall::DisclosureWhy::MacroArgsNestedTooDeep,
              "ingest: Rust macro arguments nested past the re-read's depth bound — the deeper calls are not captured (--skipped why=extract-partial)" );
}

void rereadMacroInvocation( MacroArgPass& pass, TSNode invocation, MacroArgPolicy policy, std::uint32_t depth );

// Rules (1)-(3) for one span. True when the span was accepted as code (its calls are in pass.refs).
inline bool rereadMacroArgSpan( MacroArgPass& pass, const MacroArgSpan& span, MacroArgShape shape, std::uint32_t depth )
{
    TreeGuard fragment( parseMacroArgFragment( pass.work.parser.p, pass.src, span ) );
    if( fragment.get() == nullptr )
    {
        return false;
    }
    const TSNode root = ts_tree_root_node( fragment.get() );
    if( !macroArgFragmentIsCode( root, span, shape ) )
    {
        return false;
    }
    const std::size_t firstRef = pass.refs.size();
    pass.work.defs.clear();
    pass.work.binds.clear();
    pass.work.includes.clear();
    ExtractShortfall                    fragmentShortfall;   // the fragment's tags pass has nothing of its own to disclose: the query ran for this file already
    const std::vector<PreprocDeadRange> noDeadRanges;
    captureTagsFacts( pass.cursor, pass.le, pass.fileId, pass.src, root, pass.work.defs, pass.refs, pass.work.binds, pass.work.includes, noDeadRanges,
                      fragmentShortfall );
    pass.refs.erase( std::remove_if( pass.refs.begin() + std::ptrdiff_t( firstRef ), pass.refs.end(), isRelationRow ), pass.refs.end() );
    pass.refs.erase( std::remove_if( pass.refs.begin() + std::ptrdiff_t( firstRef ), pass.refs.end(),
                                     [ & ]( const RawRef& r ) { return isMatcherLiteralCall( r, pass.matcherWords ); } ),
                     pass.refs.end() );
    const std::vector<MacroArgSite> nested = macroArgSitesIn( pass.refs, firstRef );
    forEachMacroInvocationAt( root, nested, [ & ]( TSNode invocation, const MacroArgSite& site )
    {
        rereadMacroInvocation( pass, invocation, site.policy, depth + 1u );
    } );
    return true;
}

void rereadMacroArgGroup( MacroArgPass& pass, TSNode tokenTree, std::uint32_t depth );

inline bool isMacroArgBlockGroup( TSNode node, std::string_view src ) noexcept
{
    return kindIs( ts_node_type( node ), "token_tree" ) && src[ ts_node_start_byte( node ) ] == '{';
}

// The `{ … }` groups among the direct children [first, stop) of a rejected token tree, each tried as a block.
inline void rereadMacroArgBlocks( MacroArgPass& pass, std::span<const TSNode> children, std::size_t first, std::size_t stop, std::uint32_t depth )
{
    for( std::size_t index = first; index < stop; ++index )
    {
        if( isMacroArgBlockGroup( children[ index ], pass.src ) )
        {
            rereadMacroArgGroup( pass, children[ index ], depth );
        }
    }
}

// Rule (4) for an arm body, the direct children [first, stop): tried as one expression; when it is not one, its
// `{ … }` groups are tried as blocks.
inline void rereadMacroArm( MacroArgPass& pass, std::span<const TSNode> children, std::size_t first, std::size_t stop, std::uint32_t depth )
{
    if( first >= stop )
    {
        return;
    }
    const MacroArgSpan span{ ts_node_start_byte( children[ first ] ), ts_node_start_byte( children[ stop ] ), ts_node_start_point( children[ first ] ),
                             ts_node_start_point( children[ stop ] ) };
    const bool holdsCall = pass.src.substr( span.startByte, span.endByte - span.startByte ).find( '(' ) != std::string_view::npos;
    if( holdsCall && !rereadMacroArgSpan( pass, span, MacroArgShape::Expression, depth ) )
    {
        rereadMacroArgBlocks( pass, children, first, stop, depth );
    }
}

// Rule (4) over a rejected token tree's direct children. A top-level `=>`, `,` or `;` (and the closing delimiter)
// ends a piece. A piece that follows a `=>` and ends at a `,`, a `;` or the closing delimiter is an arm body. In every
// other piece (an arm's pattern, or the tokens between two arrows when the arms are not separated) only the `{ … }`
// groups are tried.
inline void rereadRejectedMacroArgGroup( MacroArgPass& pass, TSNode tokenTree, std::uint32_t depth )
{
    std::vector<TSNode> children;
    ChildCursor         cursor( tokenTree );
    collectChildren( tokenTree, cursor.cur, children );
    std::size_t pieceFirst  = 1;       // [0] is the opening delimiter
    bool        isAfterArrow = false;
    for( std::size_t index = 1; index < children.size(); ++index )
    {
        const char* kind    = ts_node_type( children[ index ] );
        const bool  isArrow = kindIs( kind, "=>" );
        const bool  isStop  = index + 1 == children.size() || kindIs( kind, "," ) || kindIs( kind, ";" );
        if( !isArrow && !isStop )
        {
            continue;
        }
        if( isAfterArrow && isStop )
        {
            rereadMacroArm( pass, children, pieceFirst, index, depth );
        }
        else
        {
            rereadMacroArgBlocks( pass, children, pieceFirst, index, depth );
        }
        pieceFirst   = index + 1;
        isAfterArrow = isArrow;
    }
}

// A whole token tree: rule (1), and on rejection rule (4).
void rereadMacroArgGroup( MacroArgPass& pass, TSNode tokenTree, std::uint32_t depth )
{
    const MacroArgSpan span = macroArgSpanOf( tokenTree );
    if( !macroArgHoldsCallShape( pass.src, span ) || rereadMacroArgSpan( pass, span, MacroArgShape::DelimitedGroup, depth ) )
    {
        return;
    }
    if( depth >= kMacroArgNestingDepth )
    {
        discloseMacroArgNesting( pass );
        return;
    }
    rereadRejectedMacroArgGroup( pass, tokenTree, depth + 1u );
}

// A pattern macro's first argument: the tokens between the opening delimiter and the first top-level comma.
inline void rereadMacroFirstArgument( MacroArgPass& pass, TSNode tokenTree, std::uint32_t depth )
{
    TSNode      open{};
    TSNode      stop{};   // the first top-level `,`, else the closing delimiter
    ChildCursor cursor( tokenTree );
    forEachChild( tokenTree, cursor.cur, [ & ]( TSNode child )
    {
        if( ts_node_is_null( open ) )
        {
            open = child;
            return true;
        }
        stop = child;
        return !kindIs( ts_node_type( child ), "," );
    } );
    if( ts_node_is_null( stop ) || ts_node_end_byte( open ) >= ts_node_start_byte( stop ) )
    {
        return;
    }
    const MacroArgSpan span{ ts_node_end_byte( open ), ts_node_start_byte( stop ), ts_node_end_point( open ), ts_node_start_point( stop ) };
    if( pass.src.substr( span.startByte, span.endByte - span.startByte ).find( '(' ) != std::string_view::npos )
    {
        (void)rereadMacroArgSpan( pass, span, MacroArgShape::Expression, depth );
    }
}

void rereadMacroInvocation( MacroArgPass& pass, TSNode invocation, MacroArgPolicy policy, std::uint32_t depth )
{
    if( depth > kMacroArgNestingDepth )
    {
        discloseMacroArgNesting( pass );
        return;
    }
    TSNode      tokenTree{};
    ChildCursor cursor( invocation );
    forEachChild( invocation, cursor.cur, [ & ]( TSNode child )
    {
        if( kindIs( ts_node_type( child ), "token_tree" ) )
        {
            tokenTree = child;
        }
        return ts_node_is_null( tokenTree );
    } );
    if( ts_node_is_null( tokenTree ) || ts_node_end_byte( tokenTree ) > pass.src.size() )
    {
        return;
    }
    const std::span<const std::string_view> outer = pass.matcherWords;   // a nested invocation reads its own macro's matchers
    pass.matcherWords = invokedMacroMatcherWords( pass.matchers, invocation, pass.src );
    if( policy == MacroArgPolicy::FirstArgument )
    {
        rereadMacroFirstArgument( pass, tokenTree, depth );
    }
    else
    {
        rereadMacroArgGroup( pass, tokenTree, depth );
    }
    pass.matcherWords = outer;
}

// The file a tags pass just read: `root` is the tree it read, `src` its bytes.
struct MacroArgFile
{
    const LangEntry& le;
    std::uint32_t    fileId;
    std::string_view src;
    TSNode           root;
    std::span<const RawDef> defs;   // the definition rows the tags pass added for this file (its `macro_rules!` matchers)
};

/// RUST-MACRO-ARGS, right after one file's tags pass: append the calls written inside the arguments of the macro
/// invocations that pass recorded. Its rows are the trailing rows of `refs` that carry this file's id. A language without
/// `name!` macros costs one test; a file without one, one scan of those rows.
inline void rereadMacroArguments( MacroArgScratch& work, TSQueryCursor* cursor, const MacroArgFile& file, std::vector<RawRef>& refs, ExtractShortfall& shortfall )
{
    if( !langFacts( file.le.lang ).bangMacros || cursor == nullptr )
    {
        return;
    }
    std::size_t firstRefOfFile = refs.size();
    while( firstRefOfFile > 0 && refs[ firstRefOfFile - 1 ].fileId == file.fileId )
    {
        --firstRefOfFile;
    }
    const std::vector<MacroArgSite> sites = macroArgSitesIn( refs, firstRefOfFile );
    if( sites.empty() || !ts_parser_set_language( work.parser.p, file.le.grammar() ) )
    {
        return;
    }
    MacroArgPass pass{ work, cursor, file.le, file.fileId, file.src, refs, shortfall };
    const std::vector<MacroMatcherWords> matchers = fileMacroMatcherWords( file.root, file.src, file.defs );
    pass.matchers                                 = matchers;
    forEachMacroInvocationAt( file.root, sites, [ & ]( TSNode invocation, const MacroArgSite& site )
    {
        rereadMacroInvocation( pass, invocation, site.policy, 0 );
    } );
}

}   // namespace
}   // namespace rw
