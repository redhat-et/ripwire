#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_names.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_names.h — name/scope resolution and capture policy, moved VERBATIM from ingest.cpp in the
// 2026-08-29 split: the H4 qualified-name machinery (immediateScope, the C++ operator/scope
// re-split with its phantom-separator guards, cppDefNameReseat, qualifierOf, the Rust path/scope
// readers, enclosingScopeOf), in-file test-scope detection across five languages plus the LB-E
// doctest/catch2 test-macro block reader, and the capture drop gates (SCREAMING_SNAKE const
// policy, CUDA memory-space qualifiers, YAML key gating, CJS export / prototype-member / Python
// enum-member targets, dropGatedCapture). The policy layer that decides WHAT a captured name is
// and whether it deserves a symbol. Same contract as every ingest_*.h: reopens `namespace rw` and
// the unnamed namespace inside it — one TU, one unnamed namespace, internal linkage unchanged,
// zero new API surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// E#4 canonical-resolution helpers (C++; node-type names are tree-sitter-cpp's). For a call `A::b()` the
// @name node `b` sits in a qualified_identifier whose `scope` is `A` → qualifierOf returns the IMMEDIATE
// scope component ("A", or "B" from `A::B::b`). enclosingScopeOf walks ancestors to the nearest
// class/struct/namespace and returns its name (for in-class method DEFS). Both "" when absent → caller
// falls back to bare-name resolution (so non-C++ langs and unqualified calls are unaffected).
inline std::string immediateScope( std::string_view full )
{
    const std::size_t cc = full.rfind( "::" );
    return std::string( cc == std::string_view::npos ? full : full.substr( cc + 2 ) );
}

// ── H4 qualified-call re-split helpers ───────────────────────────────────────────────────────────────────
// The widened C++ call pattern (`qualified_identifier name: (_)`) binds the INNER node at every depth, so
// the captured text of a 3+-segment call still carries scope (`inner::targetFn`,
// `numeric_limits<std::size_t>::max`). These two helpers turn that text back into the (name, immediate
// qualifier) pair the canonical resolution tier keys on — the plain finalSegment() path cannot, because it
// truncates at the FIRST '<' and would name the second example `numeric_limits`.

// The four C++ cast keywords. tree-sitter-cpp parses `static_cast<T>( x )` as
// `call_expression function: (template_function name: (identifier))` — structurally identical to a real
// explicit-template-argument call — so the template_function reference pattern matches every cast in the
// tree (171 sites in this repo's src/ alone). A cast is not a call and must not mint a reference: it is
// VALID INPUT, not a corrupt invariant, so the capture loop simply skips it (never VERIFY, never
// DEGRADED_PATH_ALERT — nothing degraded). Query predicates cannot do this: passesPredicates is wired into
// --match/--lint only, not the tags pass (measured — a `#not-eq?` left --uses=static_cast at 165).
inline bool isCppCastKeyword( std::string_view name ) noexcept
{
    return name == "static_cast" || name == "reinterpret_cast" || name == "const_cast" || name == "dynamic_cast";
}

// First DIRECT child of `n` whose node type is `type`, or a null node when none exists — the one
// child-scan shape shared by the using-declaration keyword guard below and the phantom-`::` probe
// (hasPhantomScopeSeparator), so the two cannot drift into near-clones of each other.
inline TSNode firstChildOfType( TSNode n, const char* type ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < childCount; ++i )
    {
        const TSNode child = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( child ), type ) == 0 )
        {
            return child;
        }
    }
    return TSNode {};
}

// using-declaration re-exports (r9 loss bucket 1): TRUE when a C++ `using_declaration` node is a grammar
// KEYWORD form rather than a single-symbol re-export — `using namespace ns;` (its qualified spelling
// `using namespace lib::nested;` carries a qualified_identifier and so matches the tags pattern) or
// `using enum E;` (C++20; re-exports the ENUMERATORS, not the named type, so an import row for the type
// would over-claim). Both are VALID INPUT, skipped at capture time exactly like the cast keywords above:
// the grammar puts the keyword in an anonymous child with no field name, which a tags-query pattern
// cannot negate (passesPredicates is wired into --match/--lint only, never the tags pass).
inline bool usingDeclarationIsDirective( TSNode n ) noexcept
{
    return !ts_node_is_null( firstChildOfType( n, "namespace" ) ) || !ts_node_is_null( firstChildOfType( n, "enum" ) );
}

// Start index of `text`'s trailing C++ OPERATOR NAME (`operator>`, `operator<<`, `operator()`, `operator bool`),
// or npos when the name is a plain identifier. This must be consulted BEFORE any angle-depth scanning.
//
// WHY (found by the adversarial verifier, not by construction): an operator name is the one place a NAME
// legitimately carries `<`/`>` punctuation that is not a template-argument delimiter. Scanning
// `inner::operator>` right-to-left, the trailing `>` opens a group that never closes, so
// lastTopLevelScopeSep finds NO separator, the re-split is skipped, and the qualifier falls back to
// qualifierOf()'s OUTERMOST scope — measured binding `outer::inner::operator>( x, y )` to a decoy
// `outer::operator>` with ambiguous=0 and no disclosure at all. `operator>`, `operator>>`, `operator>=` and
// `operator->` are all poisoned that way; `operator<<` merely survived by luck (depth is clamped at zero, so
// its `<`s are ignored rather than balanced). Detecting the operator tail up front cures the whole family.
//
// The first two guards mirror finalSegment()'s own operator exemption (see it above) so the two cannot
// drift: the keyword must start a SEGMENT (index 0, or right after a `::`/`.`), and the character after it
// must not continue an identifier — so `operatorId` stays a plain name and takes the ordinary path.
//
// The third guard is what makes the name TRAILING, as the contract says (V3-L-2: `rfind` alone accepted
// `op::operator>::go` and split it into name `operator>::go` / qualifier `op` — unreachable from valid C++,
// since an operator cannot name a scope, but the function promised npos for anything that is not a trailing
// operator name and did not deliver it). A SYMBOLIC operator's name is the keyword plus a run of operator
// punctuation, and it must reach the END of the text; anything after that run means a further segment
// follows, so this is not the trailing name. A SPACE after the keyword instead marks the
// `operator <type>` family (conversion operators, `operator new`/`operator delete`), whose type half may
// itself contain `::` (`operator ns::Type`) — that IS the trailing name, so the punctuation run is not
// applied to it.
inline std::size_t operatorNameStart( std::string_view text ) noexcept
{
    constexpr std::string_view kOperator      = "operator";
    constexpr std::string_view kOperatorPunct = "+-*/%^&|~!=<>()[],";   // every char a C++ operator name may use

    const std::size_t op = text.rfind( kOperator );
    if( op == std::string_view::npos )
    {
        return std::string_view::npos;
    }

    const bool atSegmentStart = ( op == 0 ) || ( text[ op - 1 ] == ':' ) || ( text[ op - 1 ] == '.' );
    if( !atSegmentStart )
    {
        return std::string_view::npos;
    }

    // `operator` must be a whole token: `operatorId` is a plain identifier that merely starts with it.
    const std::size_t after = op + kOperator.size();                    // one-past `operator`
    if( after >= text.size() )
    {
        return op; // the bare keyword ends the text
    }
    if( std::isalnum( static_cast<unsigned char>( text[ after ] ) ) || text[ after ] == '_' )
    {
        return std::string_view::npos;
    }

    // `operator <type>` — the type half owns the rest of the text, `::` and all.
    if( std::isspace( static_cast<unsigned char>( text[after] ) ) )
    {
        return op;
    }

    // symbolic: the punctuation run IS the name, and it must run to the end or this is not the tail.
    std::size_t punctEnd = after;
    while( punctEnd < text.size() && kOperatorPunct.find( text[punctEnd] ) != std::string_view::npos )
    {
        ++punctEnd;
    }
    return punctEnd == text.size() ? op : std::string_view::npos;
}

// Index of the last `::` in `text` that sits at TEMPLATE-ARGUMENT DEPTH ZERO, or npos when there is none.
// Scanned in reverse (the LAST top-level separator is the one that splits name from scope), tracking `<`/`>`
// nesting so a `::` inside template arguments never splits: `tmplFn<a::B>` has NO top-level separator, while
// `numeric_limits<std::size_t>::max` has exactly one — at the `::` before `max`.
// PRECONDITION: `text` carries no trailing operator name. Depth is clamped at zero, which makes an
// operator spelling merely IGNORED rather than balanced — that is enough for `operator<<` and NOT enough for
// the `>` family, whose unmatched `>` would leave the depth pinned above zero and hide every separator. The
// caller checks operatorNameStart() first; do not weaken that ordering.
// The loop counts a 1-based CURSOR down to zero rather than the classic `for( i = n; i-- > 0; )`: that idiom
// wraps `i` to SIZE_MAX on its final test, which `-fsanitize=integer` reports as an unsigned-integer
// overflow (observed on this very function before this shape — the G1 build caught it on the fixture).
inline std::size_t lastTopLevelScopeSep( std::string_view text ) noexcept
{
    std::size_t angleDepth = 0;
    for( std::size_t cursor = text.size(); cursor > 0; --cursor )
    {
        const std::size_t charIndex = cursor - 1;
        const char        c         = text[ charIndex ];
        if( c == '>' )
        {
            ++angleDepth;
        }
        else if( c == '<' && angleDepth > 0 )
        {
            --angleDepth;
        }
        else if( c == ':' && angleDepth == 0 && charIndex > 0 && text[ charIndex - 1 ] == ':' )
        {
            return charIndex - 1;                                 // index of the FIRST ':' of the pair
        }
    }
    return std::string_view::npos;
}
// True when a qualified_identifier's `::` separator is a MISSING node — a zero-width token tree-sitter
// INSERTED during error recovery, not one that is written in the source. Recovery reaches for this shape
// whenever two identifiers sit adjacent where the grammar expected one, so `<ReturnType> name(...)` after
// an unknown leading keyword parses as `ReturnType::name` with a phantom `::`. That is exactly what MSL's
// `vertex GalleryVertexOut gallery_vertexSphere( … )` does under the C++ grammar (L4) — and the invented
// "scope" is the RETURN TYPE, so honouring it would publish `Out::f` for a free function and try to
// resolve calls against a class that never had that member. Valid C++ never produces a MISSING `::`, so
// this guard is inert on every well-formed parse.
inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept
{
    const TSNode sep = firstChildOfType( qualified, "::" );
    return !ts_node_is_null( sep ) && ts_node_is_missing( sep );   // no separator child at all → pre-existing behaviour untouched (false)
}
// The innermost `name:` link of a C++ qualified_identifier chain (C1 — the DEFINITION half of the §H4
// recursion). tree-sitter-cpp nests qualified_identifier RIGHT-recursively, so the tags pattern for an
// out-of-line definition at 2+ segments binds an INNER qualified_identifier rather than the identifier
// itself: for `void nsD::OuterD::InnerD::deep3()` the capture spans `OuterD::InnerD::deep3`. Descending to
// the last link hands back exactly the node the depth-1 pattern binds directly, which is what makes the
// widened capture need no special case anywhere downstream — three properties are restored at once:
//   * TEXT is the bare final name, so defNameFromCapture()/finalSegment() need no text re-split (the one
//     the REFERENCE side needs, because its capture may carry template arguments a '<'-truncation would
//     mangle — see lastTopLevelScopeSep). A def's captured chain is a declarator, and its final link is an
//     identifier or an operator_name, never a template_function.
//   * START BYTE is the identifier's own, so `nameByte`/`nameRow` keep pointing at the name a selector
//     (--expand=file:line, --grep attribution, the flipimpact line index) matches on.
//   * PARENT is the IMMEDIATE scope's qualified_identifier, which is the node qualifierOf() reads — so
//     `deep3` keys as `InnerD::deep3` rather than the outermost `nsD::deep3`, and the phantom-`::`
//     error-recovery guard is applied to the separator that actually qualifies the name.
// Returns `n` unchanged for every node that is not a qualified_identifier — i.e. for every capture that
// existed before this fix — so it is inert by construction on the depth-1 path.
// The hop cap is defensive only: each step moves strictly down a finite tree, so it cannot spin. A chain
// deeper than the cap would return a still-qualified node, which finalSegment() still names correctly (it
// splits on the last `::`); only the immediate-scope precision would degrade, so there is nothing here a
// DEGRADED_PATH_ALERT could truthfully claim.
inline TSNode innermostQualifiedName( TSNode n ) noexcept
{
    constexpr int kMaxQualifierHops = 32;   // `a::b::c::…` past 32 segments is not written C++
    for( int hop = 0; hop < kMaxQualifierHops; ++hop )
    {
        if( ts_node_is_null( n ) || std::strcmp( ts_node_type( n ), "qualified_identifier" ) != 0 )
        {
            break;
        }
        const TSNode inner = ts_node_child_by_field_name( n, "name", 4 );
        if( ts_node_is_null( inner ) )
        {
            break;
        }
        n = inner;
    }
    return n;
}

// The four name facts captureTagsFacts carries per match: the @name node itself, its text, its start byte
// and its 0-based row. Named as a struct so the re-seat below can hand back all four at once and be
// consumed by a structured binding.
struct DefNameFacts
{
    TSNode           node;
    std::string_view text;
    std::uint32_t    byte;
    std::uint32_t    row;
};

// C1 (memgraph F1): the re-seat a C++ out-of-line DEFINITION needs when the tags pattern bound an INNER
// qualified_identifier — i.e. when the definition was written with two or more qualifier segments. Returns
// the innermost link's four facts, or a NULL node meaning "nothing to re-seat", which is the answer for
// every capture that existed before this fix (a bare identifier/operator_name is not a qualified_identifier,
// so innermostQualifiedName hands it straight back).
//
// `applies` carries the caller's whole precondition (this is a DEFINITION capture, in a C++ file) rather
// than being tested at the call site: captureTagsFacts is the file's largest function and every branch
// point spent there is measured — see the note at the bottom of this comment.
//
// The descent has to happen before ANY consumer reads the facts — the gated-capture drop, the RawDef built
// from them, and qualifierOf()'s parent lookup must all see exactly what the depth-1 pattern hands over.
//
// DEFS ONLY, deliberately. The REFERENCE path's capture may carry template arguments (`numeric_limits<
// std::size_t>::max`) that its own text re-split (operatorNameStart + lastTopLevelScopeSep) is written to
// survive; descending there would change resolved edges, which §H4's arms pin and this fix has no business
// moving. A definition's chain is a declarator, whose final link is an identifier or an operator_name.
//
// This lives OUTSIDE captureTagsFacts for the reason defNameFromCapture states above: that function is
// already the file's largest and well over the complexity bar, and a branch buried in it is both invisible
// and a measured --quality-delta regression (this one scored +11 cx / +27 LOC inline before it moved here).
inline DefNameFacts cppDefNameReseat( bool applies, TSNode nameNode, std::string_view src ) noexcept
{
    constexpr DefNameFacts kNoReseat { TSNode {}, {}, 0u, 0u };
    if( !applies || ts_node_is_null( nameNode ) )
    {
        return kNoReseat;
    }
    const TSNode inner = innermostQualifiedName( nameNode );
    if( ts_node_eq( inner, nameNode ) )
    {
        return kNoReseat;
    }
    const std::uint32_t a = ts_node_start_byte( inner );
    const std::uint32_t b = ts_node_end_byte( inner );
    if( a > b || b > src.size() )
    {
        return kNoReseat;   // out-of-range span — keep the capture's own facts, exactly as the caller did
    }
    return { inner, src.substr( a, b - a ), a, ts_node_start_point( inner ).row };
}
inline std::string qualifierOf( TSNode nameNode, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "qualified_identifier" ) != 0 )
    {
        return {};
    }
    if( hasPhantomScopeSeparator( parent ) )
    {
        return {}; // error-recovery artefact, not a written qualification
    }
    const TSNode scope = ts_node_child_by_field_name( parent, "scope", 5 );
    if( ts_node_is_null( scope ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( scope ), b = ts_node_end_byte( scope );
    return ( a <= b && b <= src.size() ) ? immediateScope( src.substr( a, b - a ) ) : std::string{};
}
// ── H4 RUST qualified-call helpers (W1-MEASURE verdict) ─────────────────────────────────────────────────
// W1 measured that the Rust PATTERN ALONE under-delivers: Rust defs carried scope="" (canonByName was fed
// only by the C++/Python arms) and Rust refs carried qualifier="", so every widened `Widget::new()` fell to
// the BARE-NAME spray — and two types defining `new` in DIFFERENT directories then hit the tier-3
// unique-or-DROP rule, killing BOTH edges with no `amb=` and no `unresolved=` movement. So the pattern ships
// WITH a qualifier (ref side) and a scope (def side); together they key the canonical `qualifier::name` tier
// that C++ already uses, and idiomatic Rust resolves PRECISELY instead of silently vanishing.


// True when `s` is spelled as a plain Rust identifier. The qualifier is a canonByName KEY half, so a segment
// that is not an identifier (`<T as Trait>`, a stray `>` from an unbalanced spelling) can only ever produce a
// key that matches nothing — returning "" instead routes the ref to the bare-name ladder, which is the honest
// fallback. Cheap, and it keeps garbage out of a lookup table.
inline bool isRustIdentifier( std::string_view s ) noexcept
{
    if( s.empty() || ( s[0] >= '0' && s[0] <= '9' ) )
    {
        return false;
    }
    for( const char c : s )
    {
        if( !( ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' ) )
        {
            return false;
        }
    }
    return true;
}

// The LAST segment of a Rust path spelling — the qualifier a `path::name` call keys on.
//   `Widget`                          → "Widget"        (2-segment `Widget::new()`)
//   `util::deep`                      → "deep"          (3-segment `util::deep::deepfn()`; immediate scope, as C++)
//   `Vec::<u32>`                      → "Vec"           (TURBOFISH, decided below)
//   `std::collections::HashMap::<K,V>` → "HashMap"
//   `<T as Trait>`                    → ""              (not an identifier → bare-name ladder)
// TURBOFISH DECISION (the round owes this one explicitly): Rust spells type arguments in expression position
// as `Vec::<u32>`, i.e. the `::` SURVIVES stripping the `<…>` group, where C++'s `Vec<u32>` does not. So the
// order is: strip the trailing balanced group FIRST (namesplit::stripTemplateArgs — never rfind, which would
// split inside `Foo<a::B>`), THEN drop the separator the turbofish left behind, THEN take the last TOP-LEVEL
// `::` segment. `Vec::<u32>` → `Vec::` → `Vec` → qualifier "Vec", which is the type the call actually names.
inline std::string rustPathSegment( std::string_view pathText ) noexcept
{
    std::string_view text = namesplit::stripTemplateArgs( pathText );          // `Vec::<u32>` → `Vec::`
    if( text.size() >= 2 && text.substr( text.size() - 2 ) == "::" )
    { // the turbofish `::<` separator
        text.remove_suffix( 2 );
    }
    const std::size_t sep = lastTopLevelScopeSep( text );
    const std::string_view seg = ( sep == std::string_view::npos ) ? text : text.substr( sep + 2 );
    return isRustIdentifier( seg ) ? std::string( seg ) : std::string{};
}

// The nearest enclosing Rust scope owner's NAME, walking ancestors from `node`.
//   `impl Widget { … }` / `impl Trait for Widget { … }` → the `type:` field ("Widget") — the IMPLEMENTOR in
//        both spellings, which is exactly what a caller writes before `::`. `impl<T> Foo<T>` → "Foo".
//   `trait Shape { fn area(&self) { … } }` → "Shape"  (a defaulted trait method is called `Shape::area`)
//   `mod util { … }`                      → "util"    (only when `includeModules`)
// `includeModules=false` is the `Self::` resolution mode: `Self` is only meaningful inside an impl/trait, so a
// module must NOT be allowed to answer for it. Node kinds are Rust-unique, which is why this stays a separate
// function from enclosingScopeOf rather than three more arms in its shared list.
inline std::string rustEnclosingScopeOf( TSNode node, std::string_view src, bool includeModules )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        const bool  isImpl  = std::strcmp( t, "impl_item" )  == 0;
        const bool  isTrait = std::strcmp( t, "trait_item" ) == 0;
        const bool  isMod   = includeModules && std::strcmp( t, "mod_item" ) == 0;
        if( !isImpl && !isTrait && !isMod )
        {
            continue;
        }

        // impl carries the implementor under `type:`; trait/mod carry their own `name:`. Anonymous/ill-formed
        // (empty text) yields "" — no usable scope — which is the same degrade as "no owner above".
        const TSNode owner = isImpl ? ts_node_child_by_field_name( p, "type", 4 ) : ts_node_child_by_field_name( p, "name", 4 );
        // V3 L-1: a container is not its OWN scope. `mod util { … }`'s definition node IS that `name:` child, so
        // the first ancestor found is the module itself and `util` would be published as `util::util` (likewise
        // `Shape::Shape`) — a self-scope in the canonical-id space, which is what ids are keyed on. Keep walking
        // to the NEXT owner instead, so a nested `mod deep` inside `mod util` still scopes to "util".
        if( !ts_node_is_null( owner ) && ts_node_eq( owner, node ) )
        {
            continue;
        }
        return rustPathSegment( nodeTextOf( owner, src ) );                      // `Foo<T>` → "Foo"; `a::B` → "B"
    }
    return {};
}

// Qualifier of a Rust CALL reference whose @name is the final segment of a `scoped_identifier`:
// `Widget::new()` → "Widget", `util::deep::deepfn()` → "deep", `Vec::<u32>::new()` → "Vec".
// Returns "" for every other shape (bare `free()`, `w.bump()`, `generic::<u32>()`, and the crate-root `::f()`
// spelling, which has no `path:` child) → those keep the pre-existing bare-name resolution untouched.
// This is a CALL ref (isInherit=false). graph.h's Rust `impl Trait for T` CHA path reads `qualifier` too, but
// only behind `if( !ir.isInherit ) continue;`, so the two uses of the field cannot collide — gated by
// test/rustqualcheck.sh §8.
inline std::string rustQualifierOf( TSNode nameNode, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "scoped_identifier" ) != 0 )
    {
        return {};
    }

    std::string qualifier = rustPathSegment( nodeTextOf( ts_node_child_by_field_name( parent, "path", 4 ), src ) );
    // `Self::helper()` — resolve `Self` to the ENCLOSING impl/trait type at EXTRACTION time, so the ref keys
    // the same canonical entry the def side wrote (`Widget::helper`). Precedent: captureRustImpls already
    // reads an impl header's `type:` for inherit refs. Falls back to bare-name when there is no impl above.
    if( qualifier == "Self" )
    {
        qualifier = rustEnclosingScopeOf( nameNode, src, /*includeModules=*/false );
    }
    return qualifier;
}

inline std::string enclosingScopeOf( TSNode node, std::string_view src )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        // class/struct/namespace owners across grammars (names don't collide between grammars):
        //   C++: class_specifier/struct_specifier/namespace_definition · Python: class_definition.
        // Each exposes a `name` field; the nearest one is the enclosing scope used for canonical resolution
        // and P2-D Rule-1 narrowing (a `self.m()`/`this->m()`/bare member call resolves to scope::m).
        const bool scopeOwner =    std::strcmp( t, "class_specifier" )     == 0 || std::strcmp( t, "struct_specifier" )    == 0
                                || std::strcmp( t, "namespace_definition" ) == 0 || std::strcmp( t, "class_definition" )    == 0;
        if( scopeOwner )
        {
            const TSNode nm = ts_node_child_by_field_name( p, "name", 4 );
            if( ts_node_is_null( nm ) )
            {
                return {}; // anonymous → no usable scope
            }
            const std::uint32_t a = ts_node_start_byte( nm ), b = ts_node_end_byte( nm );
            return ( a <= b && b <= src.size() ) ? std::string( src.substr( a, b - a ) ) : std::string{};
        }
    }
    return {};
}

// F5: a Swift LOCAL binding — `let a = f()` / `var b = ...` inside a function/closure body — parses to the
// same `property_declaration` node as a real stored/computed MEMBER property, so the @definition.var pattern
// captures it as a spurious top-level `var` symbol AND (being the nearest enclosing symbol above the body's
// call sites) STEALS the enclosing function's call edges. The discriminant: a `statements` node is the body of
// an executable block (function_body / lambda_literal / if/for/while/… ) and NEVER wraps a member property
// directly — a stored member is a child of class_body/enum_class_body/source_file, and a computed member's
// `statements` live inside its `computed_property` CHILD, below (not above) the property_declaration. So a
// `statements` ANCESTOR uniquely marks a local binding. Walk up from the property node; a `statements` before
// any type-body/file scope ⇒ local. Swift-only (gated by the caller); no other grammar reaches here.
inline bool isSwiftLocalBinding( TSNode declNode ) noexcept
{
    for( TSNode p = ts_node_parent( declNode ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( std::strcmp( t, "statements" ) == 0 )
        {
            return true;                                             // inside an executable block → local binding
        }
        // a member property's wrappers — reaching one first means it is NOT a local.
        if( std::strcmp( t, "class_body" ) == 0 || std::strcmp( t, "enum_class_body" ) == 0 || std::strcmp( t, "protocol_body" ) == 0 || std::strcmp( t, "source_file" ) == 0 )
        {
            return false;
        }
    }
    return false;
}

// ── L8: IN-FILE TEST SCOPE ───────────────────────────────────────────────────────────────────────────
// filter.h::isTestPath answers "is this a test?" from the PATH alone. Four mainstream conventions put
// test code INSIDE a production source file, where no path signal exists:
//
//   Rust    `#[cfg(test)] mod tests { … }` / `#[test] fn …` inside src/*.rs — the language's OWN
//           documented convention, so essentially every crate is affected.
//   Python  `class TestFoo:` / a module-level `def test_bar():` beside production defs.
//   JS/TS   helpers declared inside a `describe(…)` / `it(…)` / `test(…)` block.
//   C#      a `[Fact]` / `[Test]` / `[TestMethod]` member beside a production class.
//
// Measured on astral-sh/ruff (5945 files) before this existed: the #1-ranked symbol of the entire map
// was `CursorTest::builder`, a `#[cfg(test)]` helper inside `crates/ty_ide/src/lib.rs`, and
// `--ignore-tests` dropped 15,811 path-classified symbols WITHOUT changing the top-5 — the top-5 were
// all in-file tests the path filter cannot see.
//
// The bit is SYNTACTIC and PRECISION-FIRST. A mis-marked production symbol vanishes from
// --ignore-tests output and is de-prioritized in retrieval, which is strictly worse than a missed
// test — so every rule below keys on a convention that is unambiguous in its own language, and
// nothing is inferred from a name that merely looks test-ish. The negative controls that pin this
// live in test/testscopecheck.sh: a non-test `mod utils`, a Python `class Testament`, a JS function
// named `describe_thing`, and an unattributed C# class next to an attributed method. What each rule
// deliberately does NOT cover is recorded at the rule itself — a documented gap, never a guess.
//
// Consumed by Symbol::testScope, which filter.h::isTestSymbol ORs with the path signal; it rides the
// per-file cache record, so kParserVer gates it like every other extraction fact.

// `a` equals `b` after every ASCII space/tab/CR/LF in `a` is removed. Attribute spellings vary
// (`cfg(test)` and `cfg( test )` are the same attribute), and the whitespace is the only variation a
// syntactic comparison must absorb — `b` is always a caller-supplied literal with none.
inline bool equalsIgnoringAsciiSpace( std::string_view a, std::string_view b ) noexcept
{
    std::size_t matched = 0;
    for( char c : a )
    {
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' )
        {
            continue;
        }
        if( matched >= b.size() || b[matched] != c )
        {
            return false;
        }
        ++matched;
    }
    return matched == b.size();
}

// One Rust attribute's inner text (the `cfg(test)` of `#[cfg(test)]`), judged as a test marker.
// MATCHES: `cfg(test)`, `test`, and any path attribute whose FINAL segment is `test` (`tokio::test`,
// `async_std::test`, `actix_rt::test` — every async runtime spells its harness that way).
// DELIBERATELY NOT MATCHED: the compound `cfg(all(test, …))` / `cfg(any(test, …))` forms. Deciding
// that such a module is test-only means reasoning about which arm a build selects, which depends on
// feature flags ripwire never sees — the same "never quietly guess" rule that keeps ppalt a
// disclosure instead of a branch choice.
inline bool rustAttrIsTestMarker( std::string_view attr ) noexcept
{
    if( equalsIgnoringAsciiSpace( attr, "cfg(test)" ) || equalsIgnoringAsciiSpace( attr, "test" ) )
    {
        return true;
    }
    const std::size_t sep = attr.rfind( "::" );
    return sep != std::string_view::npos && equalsIgnoringAsciiSpace( attr.substr( sep + 2 ), "test" );
}

// Does the contiguous attribute run PRECEDING `item` carry a test marker? Rust attributes are SIBLING
// `attribute_item` nodes in front of the item they decorate, not children of it (verified by --match
// probes on real parses, not assumed) — so the scan walks backwards and stops at the first sibling
// that is neither an attribute nor a comment, which is where this item's own attribute run began.
inline bool rustItemCarriesTestAttr( TSNode item, std::string_view src ) noexcept
{
    for( TSNode prev = ts_node_prev_sibling( item ); !ts_node_is_null( prev ); prev = ts_node_prev_sibling( prev ) )
    {
        const char* t = ts_node_type( prev );
        if( std::strcmp( t, "attribute_item" ) == 0 )
        {
            const std::uint32_t childCount = ts_node_child_count( prev );
            for( std::uint32_t ci = 0; ci < childCount; ++ci )
            {
                const TSNode ch = ts_node_child( prev, ci );
                if( std::strcmp( ts_node_type( ch ), "attribute" ) == 0 && rustAttrIsTestMarker( nodeTextOf( ch, src ) ) )
                {
                    return true;
                }
            }
            continue;
        }
        if( std::strcmp( t, "line_comment" ) == 0 || std::strcmp( t, "block_comment" ) == 0 )
        {
            continue;   // a doc comment may sit between an attribute and its item
        }
        break;
    }
    return false;
}

// Python `class Test<Something>` — the unittest/pytest convention. The character after `Test` MUST be
// uppercase or '_', which is exactly what stops `class Testament` (a real English word, and the
// gate's negative control) from matching. A class named exactly `Test` is also left alone: four
// characters are too short to be a convention and it is a plausible production type name.
inline bool pyTestClassName( std::string_view name ) noexcept
{
    if( name.size() < 5 || name.compare( 0, 4, "Test" ) != 0 )
    {
        return false;
    }
    const unsigned char after = static_cast<unsigned char>( name[4] );
    return ( after >= 'A' && after <= 'Z' ) || after == '_';
}

// A C# attribute's name, judged as a test marker: the three framework markers that are unambiguous
// across xUnit (`Fact`), NUnit (`Test`) and MSTest (`TestMethod`), matched on the FINAL segment so a
// fully-qualified `Xunit.FactAttribute`-style spelling still resolves. DELIBERATELY NOT MATCHED:
// `Theory`/`TestCase` (data-driven variants) and the class-level `[TestFixture]`/`[TestClass]` — each
// is a separate convention that deserves its own probe and its own gate arm rather than a guess here.
inline bool csharpAttrIsTestMarker( std::string_view name ) noexcept
{
    const std::size_t      dot = name.rfind( '.' );
    const std::string_view fin = ( dot == std::string_view::npos ) ? name : name.substr( dot + 1 );
    return fin == "Test" || fin == "Fact" || fin == "TestMethod";
}

// Does `n` carry a test-marking attribute? C# attribute lists are direct CHILDREN of the declaration
// they decorate (the mirror image of Rust's sibling placement — again verified by --match probe).
inline bool csharpNodeCarriesTestAttr( TSNode n, std::string_view src ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode list = ts_node_child( n, ci );
        if( std::strcmp( ts_node_type( list ), "attribute_list" ) != 0 )
        {
            continue;
        }
        const std::uint32_t attrCount = ts_node_child_count( list );
        for( std::uint32_t ai = 0; ai < attrCount; ++ai )
        {
            const TSNode attr = ts_node_child( list, ai );
            if(    std::strcmp( ts_node_type( attr ), "attribute" ) == 0
                && csharpAttrIsTestMarker( nodeTextOf( ts_node_child_by_field_name( attr, "name", 4 ), src ) ) )
            {
                return true;
            }
        }
    }
    return false;
}

// Python's rule, written as its own pass because the two halves are ORDERED: a `def test_*` counts
// only at MODULE level (the pytest convention), so the enclosing-class question must be answered
// before the name question. Walking outward once and testing names as they appear would mark a method
// named `test_bar` inside a production class — precisely the over-trigger this shape forbids.
inline bool pythonInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    bool enclosedByClass = false;
    for( TSNode n = defNode; !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        if( std::strcmp( ts_node_type( n ), "class_definition" ) != 0 )
        {
            continue;
        }
        if( pyTestClassName( nodeTextOf( ts_node_child_by_field_name( n, "name", 4 ), src ) ) )
        {
            return true;    // a member of a Test* class, at any nesting depth
        }
        enclosedByClass = true;
    }
    if( enclosedByClass || std::strcmp( ts_node_type( defNode ), "function_definition" ) != 0 )
    {
        return false;
    }
    return nodeTextOf( ts_node_child_by_field_name( defNode, "name", 4 ), src ).rfind( "test_", 0 ) == 0;
}

// Is `pred` true of `node` itself or of any of its ancestors? Three of the four in-file test rules ask
// exactly that and differ ONLY in the predicate, so the walk lives here once. Written after
// --quality-delta flagged the first hand-rolled copy as a 101-token clone of yamlKeyCaptureDropped's
// unrelated ancestor scan — the detector was right that the loop is one body, and three more copies of
// it would have been three more.
template<class NodePred>
inline bool anySelfOrAncestor( TSNode node, NodePred pred ) noexcept
{
    for( TSNode n = node; !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        if( pred( n ) )
        {
            return true;
        }
    }
    return false;
}

// Rust: the def itself, or any enclosing `mod`/`fn`, carries a test attribute.
inline bool rustInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept
                                       {
                                           const char* t = ts_node_type( n );
                                           return    ( std::strcmp( t, "mod_item" ) == 0 || std::strcmp( t, "function_item" ) == 0 )
                                                  && rustItemCarriesTestAttr( n, src );
                                       } );
}

// JS/TS: the harness block is a CALL whose callee is one of three bare identifiers, and the def is
// declared somewhere inside its arguments. The member forms (`it.only`, `test.each`, `describe.skip`)
// are a DOCUMENTED GAP, not an oversight — they need their own probe and gate arm, and the bare forms
// are what the measured corpora spell.
inline bool jsInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept
                                       {
                                           if( std::strcmp( ts_node_type( n ), "call_expression" ) != 0 )
                                           {
                                               return false;
                                           }
                                           const std::string_view callee = nodeTextOf( ts_node_child_by_field_name( n, "function", 8 ), src );
                                           return callee == "describe" || callee == "it" || callee == "test";
                                       } );
}

// C#: the def itself, or an enclosing declaration, carries a test-marking attribute list.
inline bool csharpInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept { return csharpNodeCarriesTestAttr( n, src ); } );
}

// The one entry point: is this def (or an enclosing scope of it) test code by an IN-FILE convention?
// A language with no modeled convention returns false and keeps path-only classification — a zero
// here means "no in-file convention found", never "this is production" (filter.h::isTestSymbol ORs
// the path signal back in). One flat dispatch, one walk per language: the four rules have genuinely
// different SHAPES (Rust reads preceding siblings, Python must answer the enclosing-class question
// before the name question, JS/TS reads a callee, C# reads child attribute lists), so folding them
// into a single loop bought a nested language test on every ancestor and nothing else.
inline bool inFileTestScope( TSNode defNode, std::string_view src, Lang lang ) noexcept
{
    if( ts_node_is_null( defNode ) )
    {
        return false;
    }
    switch( lang )
    {
        case Lang::Rust:       return rustInFileTestScope( defNode, src );
        case Lang::Python:     return pythonInFileTestScope( defNode, src );
        case Lang::TypeScript:
        case Lang::JavaScript: return jsInFileTestScope( defNode, src );
        case Lang::CSharp:     return csharpInFileTestScope( defNode, src );
        default:               return false;
    }
}

// ---- LB-E (r10 gitnexus harvest 2026-08-20): macro-defined test bodies ----------------------------------
// `TEST_CASE( "title" ) { … }` — doctest/Catch2's block-forming test macros — cannot be expanded by
// tree-sitter, so the source parses as TWO SIBLING nodes: an (expression_statement (call_expression …)
// (MISSING ";")) and a bare (compound_statement …). Neither is a definition, so pre-kParserVer-70 the
// body's calls attributed to NOTHING (measured on this repo: five pageRankDouble sites invisible to
// --callers) — and --test-gate/--affected/tested= all rest on exactly those test→subject edges.
// queries/cpp/tags.scm captures the SHAPE only (@definition.testmacroblock); the real gates live here.
//
// The known block-forming test macros — doctest/Catch2 STRING-TITLE forms only. The GoogleTest family
// (TEST/TEST_F/TEST_P — identifier arguments) parses as a plain function_definition and never reaches
// this shape; TEST_CASE_TEMPLATE/SCENARIO_TEMPLATE lose their block INTO the argument list to error
// recovery (no sibling compound_statement — the documented gap in queries/cpp/tags.scm); SUBCASE/
// SECTION/GIVEN/WHEN/THEN are deliberately absent because they nest INSIDE a captured test body, and
// splitting one test's calls across subcase symbols would be a worse answer than one spanning symbol.
inline constexpr std::array<std::string_view, 5> kTestBlockMacroNames = { "TEST_CASE", "TEST_CASE_FIXTURE", "TEST_CASE_METHOD", "SCENARIO", "TEST_SUITE" };

// The capture-time gate + parts for a @definition.testmacroblock candidate. PRECISION OVER RECALL: ok
// only when ALL of — the callee identifier is a known test macro (an unknown `WIDGET_DEF( "x" ) { … }`
// could be anything, and minting a phantom test symbol is worse than staying blind); the statement
// carries the error-recovery MISSING ";" (a real `logCall( "x" );` before an unrelated block inside a
// function body is the same query shape with a REAL semicolon, and must not trigger); the next named
// sibling is the compound_statement body; and a non-empty title string literal sits in the argument
// list (FIRST string wins: TEST_CASE_FIXTURE/TEST_CASE_METHOD put a fixture identifier before the
// title, Catch2's "[tags]" literal comes after it).
struct TestMacroBlockParts
{
    bool   ok = false;
    TSNode body {};    // the sibling compound_statement — adopted as the def's body
    TSNode title {};   // the title string_literal node — its content becomes the symbol's name
};

inline TestMacroBlockParts testMacroBlockPartsOf( TSNode exprStmtNode, std::string_view src ) noexcept
{
    if( ts_node_is_null( exprStmtNode ) || std::strcmp( ts_node_type( exprStmtNode ), "expression_statement" ) != 0 )
    {
        return {};
    }

    // the MISSING ";" — the one structural mark separating a macro-with-block from a real statement
    bool hasMissingSemicolon = false;
    const std::uint32_t childCount = ts_node_child_count( exprStmtNode );
    for( std::uint32_t childIx = 0; childIx < childCount; ++childIx )
    {
        if( ts_node_is_missing( ts_node_child( exprStmtNode, childIx ) ) )
        {
            hasMissingSemicolon = true;
            break;
        }
    }
    if( !hasMissingSemicolon )
    {
        return {};
    }

    const TSNode body = ts_node_next_named_sibling( exprStmtNode );
    if( ts_node_is_null( body ) || std::strcmp( ts_node_type( body ), "compound_statement" ) != 0 )
    {
        return {};
    }

    // the callee must be a KNOWN test macro
    const TSNode call = ts_node_named_child( exprStmtNode, 0 );
    if( ts_node_is_null( call ) || std::strcmp( ts_node_type( call ), "call_expression" ) != 0 )
    {
        return {};
    }
    const std::string_view callee = nodeTextOf( ts_node_child_by_field_name( call, "function", 8 ), src );
    bool isKnownMacro = false;
    for( const std::string_view macroName : kTestBlockMacroNames )
    {
        if( callee == macroName )
        {
            isKnownMacro = true;
            break;
        }
    }
    if( !isKnownMacro )
    {
        return {};
    }

    // the FIRST string literal among the arguments is the title
    const TSNode args = ts_node_child_by_field_name( call, "arguments", 9 );
    const std::uint32_t argCount = ts_node_is_null( args ) ? 0u : ts_node_named_child_count( args );
    for( std::uint32_t argIx = 0; argIx < argCount; ++argIx )
    {
        const TSNode arg = ts_node_named_child( args, argIx );
        if( std::strcmp( ts_node_type( arg ), "string_literal" ) == 0 && ts_node_end_byte( arg ) > ts_node_start_byte( arg ) + 2 )   // "" is not a name
        {
            return { true, body, arg };
        }
    }
    return {};
}

// the title text: the string_literal's content with the delimiting quotes stripped. Escape sequences
// stay as written — the title is a DISPLAY string, not an identifier (its consumer bypasses
// defNameFromCapture on purpose: finalSegment would split a dotted title like "rank.step determinism").
inline std::string_view testMacroTitleOf( TSNode titleNode, std::string_view src ) noexcept
{
    std::string_view raw = nodeTextOf( titleNode, src );
    if( raw.size() >= 2 && raw.front() == '"' && raw.back() == '"' )
    {
        raw.remove_prefix( 1 );
        raw.remove_suffix( 1 );
    }
    return raw;
}

// r3 q10 (bench/headtohead/r3-headroom-2026-08-03 REPORT.md §(v) item 1): SCREAMING_SNAKE — an
// ALL-CAPS identifier of ≥2 chars ([A-Z][A-Z0-9_]+), the cross-language naming convention for a
// module-level settings/config constant. The ≥2 floor drops single-letter names (a top-level `X = …`
// is a scratch binding, not a settings table). Pure ASCII on purpose: the convention IS ASCII.
inline bool isScreamingSnakeName( std::string_view name ) noexcept
{
    if( name.size() < 2 || name[0] < 'A' || name[0] > 'Z' )
    {
        return false;
    }
    for( const char c : name )
    {
        const bool ok = ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
        if( !ok )
        {
            return false;
        }
    }
    return true;
}

// Which languages' @definition.constant captures are gated on SCREAMING_SNAKE. These grammars' new
// constant patterns (queries/*/tags.scm, r3 q10) structurally capture EVERY module-level binding of the
// right shape — the name gate is what scopes extraction to settings modules / feature-flag tables
// instead of every literal. Enforced HERE because tags-pass predicates never run (#match? is wired into
// --match/--lint only — measured; see the note in queries/cpp/tags.scm). Deliberately NOT gated:
// Python (vendored upstream pattern, case-blind since import — existing behavior pinned by constcheck),
// Go (const/var patterns predate this and Go constants are conventionally CamelCase), Rust (const_item/
// static_item are constants by construction — the keyword, not the case, is the evidence), Swift
// (property_declaration predates this, filtered by isSwiftLocalBinding instead).
inline bool constCaptureNeedsScreamingGate( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::TypeScript:
        case Lang::JavaScript:
        case Lang::Ruby:
        case Lang::Java:
        case Lang::CSharp:
        case Lang::C:
        case Lang::Cpp:
        {
            return true;
        }
        default:
        {
            return false;
        }
    }
}

// Was this @name bound through an init_declarator (the r3 q10 initialized-binding patterns), or through
// the UNINITIALIZED CUDA memory-space patterns (cudacheck §7b close-out)? The two pattern families share
// one capture name, and pattern_index would be brittle against .scm reordering — the name node's ancestry
// up to the captured declaration is the robust discriminator.
inline bool nameBoundByInitDeclarator( TSNode nameNode, TSNode declNode ) noexcept
{
    for( TSNode walk = ts_node_parent( nameNode ); !ts_node_is_null( walk ) && !ts_node_eq( walk, declNode ); walk = ts_node_parent( walk ) )
    {
        if( std::strcmp( ts_node_type( walk ), "init_declarator" ) == 0 )
        {
            return true;
        }
    }
    return false;
}

// The one direct-child token scanner behind the three qualifier tests below (CUDA memory-space,
// const evidence, static storage). Filters `node`'s DIRECT children to named `namedChildType` nodes
// — plus, when acceptAnonymousToken, anonymous token children (the CUDA `__device__` shape, which
// tree-sitter-cuda parses as an anonymous child; see cudaMemorySpaceQualifierOf's contract note) —
// and returns the first child whose source text is one of `tokens` ("" = none).
inline std::string_view childTokenAmong( TSNode node, std::string_view src, const char* namedChildType, bool acceptAnonymousToken, std::initializer_list<std::string_view> tokens ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( node );
    for( std::uint32_t childIx = 0; childIx < childCount; ++childIx )
    {
        const TSNode child   = ts_node_child( node, childIx );
        const bool   isNamed = ts_node_is_named( child );
        if( isNamed && std::strcmp( ts_node_type( child ), namedChildType ) != 0 )
        {
            continue;
        }
        if( !isNamed && !acceptAnonymousToken )
        {
            continue;
        }
        const std::uint32_t beginByte = ts_node_start_byte( child );
        const std::uint32_t endByte   = ts_node_end_byte( child );
        if( endByte > src.size() || beginByte >= endByte )
        {
            continue;
        }
        const std::string_view text = src.substr( beginByte, endByte - beginByte );
        for( const std::string_view token : tokens )
        {
            if( text == token )
            {
                return text;
            }
        }
    }
    return {};
}

// CUDA memory-space qualifier of a module-scope declaration ("" = none). The uninitialized-declaration
// patterns in queries/cpp/tags.scm are STRUCTURAL and unconstrained on purpose — that query also
// compiles against tree-sitter-cpp (.cpp/.h/.metal), which has no `__constant__` token, so naming it
// there would make ts_query_new reject the whole query; tags-pass predicates never run (measured; see
// the cast-keyword note in tags.scm); and a `(type_qualifier)` child constraint cannot see `__device__`
// anyway — tree-sitter-cuda parses `__constant__`/`__managed__` as NAMED type_qualifier nodes but
// `__device__` as an ANONYMOUS token child of the declaration. The qualifier test therefore lives here,
// isCppCastKeyword's home, scanning ALL children and accepting the three spellings from exactly two node
// shapes: a named type_qualifier, or an anonymous token. The anonymous-only restriction on the second
// arm is a correctness guard, not pedantry: tree-sitter-cpp error-recovers `__device__ float x;` in a
// plain .cpp by parsing `__device__` as a NAMED type_identifier — text alone would false-positive there.
// This function is what makes the unconstrained patterns safe: every non-CUDA raw match returns "" and
// drops. Verified the strong way on the 2026-08-10 port round — the full maps of ripwire's own src/ and
// of four real C++/CUDA trees (xformers 6e10bd2, dgl f0b7cc9, MONAI 052dbb4, transformers 343c8cb86)
// are byte-identical to the pre-port binary's except for rows carrying a memory-space qualifier in a
// .cu/.cuh. (Measurement trap, recorded so it isn't re-tripped: baseline against a build of the tree you
// started from, never the PATH-installed ripwire, which can predate the r3 q10 patterns entirely.)
inline std::string_view cudaMemorySpaceQualifierOf( TSNode declNode, std::string_view src ) noexcept
{
    return childTokenAmong( declNode, src, "type_qualifier", /*acceptAnonymousToken=*/true, { "__constant__", "__device__", "__managed__" } );
}

// Does this C-family declaration (or field_declaration) carry const evidence — a `const` /
// `constexpr` / `constinit` type_qualifier as a DIRECT child? The keyword, not the name case, is
// what marks a deliberate module constant (the Rust const_item rationale, already applied to CUDA
// `__constant__` above), and it is what the 2026-08-12 census said agents actually hunt: 613 of
// 2 870 symbol-name lookups were constant-shaped, and this repo's own `constexpr std::uint32_t
// kParserVer` was invisible to its own `--for`/`--uses` because the r3 q10 gate is SCREAMING-only.
// Direct children only, on purpose: a declaration-level qualifier (`const char* k = …`, east-const
// `int const k = …`, `static const int k = …`) is the module-constant shape; a qualifier nested
// inside a pointer_declarator (`char* const k = …`, a const POINTER) stays outside this test and
// keeps the old SCREAMING-only behavior — a disclosed boundary, not a silent miss. `consteval` is
// function-only and cannot appear here; `volatile`/`restrict`/`_Atomic` are not const evidence.
inline bool declarationCarriesConstQualifier( TSNode declNode, std::string_view src ) noexcept
{
    return !childTokenAmong( declNode, src, "type_qualifier", /*acceptAnonymousToken=*/false, { "const", "constexpr", "constinit" } ).empty();
}

// The keep decision for the class-static-constant field_declaration captures (queries/cpp/tags.scm,
// module-constant round). The pattern is deliberately loose — it matches EVERY default-member-
// initializer, because tags-pass predicates never run and static/constexpr child order is free — so
// this is where the real contract lives: keep iff the field carries BOTH a `static`
// storage_class_specifier AND a const/constexpr/constinit type_qualifier. That keeps
// `static constexpr int kMaxDepth = 3;` case-blind (one per-class constant, the census target) and
// drops the two per-instance shapes the fixture pins as negatives: a plain default-initialized
// member (`int retries = 3;` — no static, no const) and a const NON-static member (`const int x = 1;`
// — per-instance state that happens to be immutable, not a class constant).
inline bool fieldConstantCaptureKept( TSNode fieldDeclNode, std::string_view src ) noexcept
{
    const bool isStaticMember = !childTokenAmong( fieldDeclNode, src, "storage_class_specifier", /*acceptAnonymousToken=*/false, { "static" } ).empty();
    return isStaticMember && declarationCarriesConstQualifier( fieldDeclNode, src );
}

// The keep decision for the @definition.field captures (member-variable round, card A3; queries/cpp,
// queries/c, queries/python tags.scm). The patterns are LOOSE on purpose — tags-pass predicates never run
// — so the contract lives here, per language:
//   C/C++ : keep iff the field_declaration carries NO `static` storage_class_specifier. A class-static
//           CONSTANT keeps its own @definition.constant row (t="var", fieldConstantCaptureKept); a mutable
//           static member is not per-object state and is not extracted at all (disclosed in the member
//           legend). Bitfields, references, pointers and arrays all keep — the declarator shape is the
//           query's business, the storage class is this function's.
//   Python: the annotated class-body attribute (`x: T [= v]`, @name's parent is the assignment itself) keeps
//           unconditionally — the `type:` field already discriminated it. The `self.x = …` form (@name's
//           parent is an `attribute`) keeps iff the receiver is the bare identifier `self` AND the assignment
//           sits inside a function_definition that sits inside a class_definition — `obj.x = …` in a free
//           function, `cls.x = …`, and a module-level `self.x` (no class) all drop. The per-(class, name)
//           first-wins dedup is ingest_sidecap.h's, after this gate.
// Pure syntactic, allocation-free; `noexcept` like its siblings.
inline bool fieldCaptureKept( Lang lang, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    if( lang == Lang::Cpp || lang == Lang::C )
    {
        return childTokenAmong( roleNode, src, "storage_class_specifier", /*acceptAnonymousToken=*/false, { "static" } ).empty();
    }
    if( lang != Lang::Python )
    {
        return false;   // no other grammar carries the capture — a query that grew one would need its own arm here
    }
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    if( std::strcmp( ts_node_type( parent ), "assignment" ) == 0 )
    {
        return true;    // the annotated class-body attribute — the query's own class_definition/type: shape did the work
    }
    if( std::strcmp( ts_node_type( parent ), "attribute" ) != 0 )
    {
        return false;
    }
    const TSNode object = ts_node_child_by_field_name( parent, "object", 6 );
    if( ts_node_is_null( object ) || std::strcmp( ts_node_type( object ), "identifier" ) != 0 || nodeTextOf( object, src ) != "self" )
    {
        return false;   // `obj.x = …` / `cls.x = …` — not an instance attribute of the enclosing class
    }
    bool sawFunction = false;
    for( TSNode up = ts_node_parent( roleNode ); !ts_node_is_null( up ); up = ts_node_parent( up ) )
    {
        const char* ut = ts_node_type( up );
        if( std::strcmp( ut, "function_definition" ) == 0 )
        {
            sawFunction = true;
        }
        else if( std::strcmp( ut, "class_definition" ) == 0 )
        {
            return sawFunction;   // a method of this class (or a closure inside one) → keep; a class-body `self.x` → drop
        }
    }
    return false;       // no enclosing class — `self` is just a name here
}

// forward declarations for dropGatedCapture below — the helpers live after nodeTextOf's section.
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPyEnumMemberTarget( TSNode nameNode, std::string_view src ) noexcept;

// The @definition.constant drop decision, in its own function for the same reason isCjsExportTarget and
// isPyEnumMemberTarget have theirs: dropGatedCapture is a dispatcher, and this is the one arm with a
// policy rather than a predicate. r3 q10 gates on SCREAMING_SNAKE; the §7b close-out adds the CUDA
// memory-space policy, C++ ONLY, as ONE decision covering both declaration shapes queries/cpp/tags.scm
// now captures. `__constant__` keeps case-blind whether initialized or not (constant by construction:
// device-read-only, host-filled via cudaMemcpyToSymbol or an initializer — the Rust const_item
// rationale; measured against NVIDIA/cuda-samples, where dxtc's initialized `kColorMetric = {…}` and
// bilateralFilter's uninitialized `cGaussian[64]` are the same kind of table). `__device__`/`__managed__`
// are MUTABLE device globals and keep only under the convention gate. An uninitialized capture with NO
// memory-space qualifier drops — the extern-const/static/alignas/volatile shape plain C++ produces by the
// hundred, which reaches here ONLY through the new structural patterns.
//
// The C-family narrowing is load-bearing, NOT a restatement of the old gate's language set:
// nameBoundByInitDeclarator is a C-family node test, and the other gated languages bind their
// @definition.constant through variable_declarator (TS/JS), field_declaration (Java/C#) or a bare
// assignment (Ruby) — every one of them would read "uninitialized" here and, having no memory-space
// qualifier either, drop WHOLESALE. Lang::C takes its own arm (module-constant round, 2026-08-12):
// queries/c/tags.scm still has no uninitialized pattern, so const-evidence-or-SCREAMING on the
// initialized shape is C's whole decision. (The 2026-08-10 measurement below predates that arm and
// pinned the CUDA port's zero-regression claim: byte-identical maps on ripwire's own src/ and 0
// added / 0 REMOVED rows on cpython 8463cb5, numpy a905925, meson f0851c9e, xformers 6e10bd2,
// dgl f0b7cc9 and transformers 343c8cb86 — ~250K symbol rows of C/C++. The module-constant round
// deliberately ADDS rows on those trees — const-qualified camel constants — which is the fix, and
// test/moduleconstcheck.sh is the gate that measures it.)
inline bool dropConstantCapture( Lang lang, std::string_view name, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    // MODULE-CONSTANT ROUND (2026-08-12): in the C family, a const/constexpr/constinit qualifier on the
    // captured declaration keeps the binding CASE-BLIND — the keyword is the evidence, exactly the
    // `__constant__` / Rust const_item rationale below. C first: its tags.scm binds only initialized
    // file-scope declarations, so const evidence (or the r3 q10 SCREAMING convention) is the whole test.
    if( lang == Lang::C )
    {
        return !( isScreamingSnakeName( name ) || declarationCarriesConstQualifier( roleNode, src ) );
    }
    if( lang != Lang::Cpp )
    {
        return constCaptureNeedsScreamingGate( lang ) && !isScreamingSnakeName( name );
    }
    // Class-static constants bind through a field_declaration (the loose default_value pattern), never
    // through init_declarator — their whole keep contract lives in fieldConstantCaptureKept.
    if( std::strcmp( ts_node_type( roleNode ), "field_declaration" ) == 0 )
    {
        return !fieldConstantCaptureKept( roleNode, src );
    }
    // Cost ordering: the common plain-C++ case (initialized + SCREAMING) resolves before any node scan,
    // and the qualifier/CUDA scans run only for non-SCREAMING names or the uninitialized CUDA patterns.
    const bool initialized = nameBoundByInitDeclarator( nameNode, roleNode );
    if( initialized && ( isScreamingSnakeName( name ) || declarationCarriesConstQualifier( roleNode, src ) ) )
    {
        return false;                                                    // r3 q10 convention keep, or const-keyword evidence
    }
    const std::string_view memSpace = cudaMemorySpaceQualifierOf( roleNode, src );
    if( memSpace == "__constant__" )
    {
        return false;                                                    // constant by construction — case-blind
    }
    if( initialized )
    {
        return true;                                                     // initialized MUTABLE non-SCREAMING global
    }
    return !( !memSpace.empty() && isScreamingSnakeName( name ) );        // uninitialized: __device__/__managed__ gated
}

// YAML's @definition.yamlkey gate — the yaml tier's one in-C++ predicate (see queries/yaml/tags.scm's
// header for why the depth cut cannot live in the query: sequence nesting between a pair and its
// document is unbounded, so no finite pattern set expresses it, and tags-pass predicates never run).
// A mapping key is a symbol iff its MAPPING depth is <= 2 — block and flow mappings counted alike
// (flow is a presentation style of the same mapping node), sequences counted NOT AT ALL (sequence
// transparency: 25.3% of real keys sit directly inside a sequence element — the steps:/containers:/
// tasks: shape — and a root-depth rule drops every one of them; 44.0% captured vs JSON's-rule 27.1%,
// measured on the 90-repo breadth corpus). Depth = the number of mapping nodes on the ancestor chain
// from the pair to the root, the pair's own mapping included; multi-document streams need no special
// case because documents never nest. The merge key `<<` (0.22% of files) is the one TEXTUAL drop —
// it parses as an ordinary plain_scalar key and a symbol named `<<` helps nobody. Alias-as-key
// (measured 0 in 4 449 files) and explicit block-node keys are dropped STRUCTURALLY by the query's
// scalar-only alternation and never reach here.
inline bool yamlKeyCaptureDropped( std::string_view name, TSNode roleNode ) noexcept
{
    if( name == "<<" )
    {
        return true;
    }
    std::uint32_t mappingDepth = 0;
    for( TSNode p = roleNode; !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "block_mapping" ) == 0 || std::strcmp( pt, "flow_mapping" ) == 0 )
        {
            if( ++mappingDepth > 2u )
            {
                return true;
            }
        }
    }
    return false;
}

// The whole drop decision for every GATED definition capture, kept out of captureTagsFacts (which is
// already the file's densest dispatch point) behind ONE call, keyed on the @definition capture's own
// name. @definition.constant delegates to dropConstantCapture above (r3 q10's SCREAMING_SNAKE gate plus
// the §7b CUDA memory-space policy); @definition.enummember (the Python shape round,
// test/pyshapecheck.sh) drops when the enclosing class's base NAME is not an enum family;
// @definition.cjsexport / @definition.protomethod (the JS shape round, test/jsshapecheck.sh) drop when
// the LEFT side is not really exports/module.exports/.prototype. — the query captures every `a.b = fn`
// shape and cannot text-test, because tags-pass predicates never run (see constCaptureNeedsScreamingGate
// above).
inline bool dropGatedCapture( std::string_view defCapSv, Lang lang, std::string_view name, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    if( defCapSv == "definition.constant" )
    {
        return dropConstantCapture( lang, name, nameNode, roleNode, src );
    }
    if( defCapSv == "definition.field" )
    {
        return !fieldCaptureKept( lang, nameNode, roleNode, src );   // member-variable round: static members / non-self targets drop
    }
    if( defCapSv == "definition.cjsexport" )
    {
        return !isCjsExportTarget( nameNode, src );
    }
    if( defCapSv == "definition.protomethod" )
    {
        return !isPrototypeMemberTarget( nameNode, src );
    }
    if( defCapSv == "definition.enummember" )
    {
        return !isPyEnumMemberTarget( nameNode, src );
    }
    if( defCapSv == "definition.yamlkey" )
    {
        return yamlKeyCaptureDropped( name, roleNode );
    }
    if( defCapSv == "definition.testmacroblock" )
    {
        // LB-E: the query captures the shape only (any identifier-call statement before a block) —
        // the name-list, MISSING-";", sibling-body and title gates all live in testMacroBlockPartsOf.
        return !testMacroBlockPartsOf( roleNode, src ).ok;
    }
    if( defCapSv == "definition.macro" )
    {
        // macro-edges round: an EMPTY-body function-like `#define NOOP(x)` defines nothing callable — drop
        // it before it mints a symbol. The @name capture's parent IS the preproc node; object-like
        // preproc_def and Rust macro_definition fail the node-type test and are never gated.
        const TSNode defineNode = ts_node_parent( nameNode );
        return !ts_node_is_null( defineNode )
            && std::strcmp( ts_node_type( defineNode ), "preproc_function_def" ) == 0
            && !preprocFunctionDefHasBody( defineNode, src );
    }
    return false;
}

// JS shape round (test/jsshapecheck.sh): the two assignment-shape gates dropGatedCapture dispatches to.
// Both helpers take the @name capture — the `property:` field of the assignment's LEFT
// member_expression — and inspect that node's `object:` sibling.

// `exports.NAME = fn` (object is the bare identifier `exports`) or `module.exports.NAME = fn` (object is
// the member_expression `module.exports`, tested segment-by-segment, not as flat text — `module . exports`
// with interior spacing would still pass, a decoy like `moduleLike.exports` cannot).
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode member = ts_node_parent( nameNode );
    if( ts_node_is_null( member ) )
    {
        return false;
    }
    const TSNode obj = ts_node_child_by_field_name( member, "object", 6 );
    if( ts_node_is_null( obj ) )
    {
        return false;
    }
    const char* objType = ts_node_type( obj );
    if( std::strcmp( objType, "identifier" ) == 0 )
    {
        return nodeTextOf( obj, src ) == "exports";
    }
    if( std::strcmp( objType, "member_expression" ) == 0 )
    {
        const TSNode oo = ts_node_child_by_field_name( obj, "object", 6 );
        return std::strcmp( ts_node_type( oo ), "identifier" ) == 0
            && nodeTextOf( oo, src ) == "module"
            && nodeTextOf( ts_node_child_by_field_name( obj, "property", 8 ), src ) == "exports";
    }
    return false;
}

// `Foo.prototype.NAME = fn` at any qualifier depth: the member_expression under `object:` must name
// `prototype` as its property. Instance-slot assignments (`sock.onclose = fn`, `this.state.h = fn`)
// share the captured shape and fail exactly this test.
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode member = ts_node_parent( nameNode );
    if( ts_node_is_null( member ) )
    {
        return false;
    }
    const TSNode obj = ts_node_child_by_field_name( member, "object", 6 );
    if( ts_node_is_null( obj ) || std::strcmp( ts_node_type( obj ), "member_expression" ) != 0 )
    {
        return false;
    }
    return nodeTextOf( ts_node_child_by_field_name( obj, "property", 8 ), src ) == "prototype";
}

// Python shape round (test/pyshapecheck.sh): `NAME = value` in a class body is a definition only when
// the class IS an enum table — otherwise it is the plain data attr the tags.scm scope line keeps out
// (12 131 django sites, re-measured 2026-08-10 at @c334c1a8ff). Enum-ness is read off the base NAME
// list (the class_definition's `superclasses` argument_list): the stdlib enum family plus django's
// Choices family, which is enum.Enum-derived and carries the bulk of django's own member sites.
// A base the name does not reveal (a subclass-of-a-subclass behind an alias) stays out: base names
// are checked statically, never resolved — the gate pins that direction too.
inline bool isPyEnumMemberTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode assign = ts_node_parent( nameNode );                                    // assignment
    const TSNode stmt   = ts_node_is_null( assign ) ? assign : ts_node_parent( assign );  // expression_statement
    const TSNode body   = ts_node_is_null( stmt )   ? stmt   : ts_node_parent( stmt );    // block
    const TSNode cls    = ts_node_is_null( body )   ? body   : ts_node_parent( body );    // class_definition
    if( ts_node_is_null( cls ) || std::strcmp( ts_node_type( cls ), "class_definition" ) != 0 )
    {
        return false;
    }
    const TSNode bases = ts_node_child_by_field_name( cls, "superclasses", 12 );
    if( ts_node_is_null( bases ) )
    {
        return false;
    }
    const std::uint32_t baseCount = ts_node_named_child_count( bases );
    for( std::uint32_t baseIndex = 0; baseIndex < baseCount; ++baseIndex )
    {
        TSNode base = ts_node_named_child( bases, baseIndex );
        if( std::strcmp( ts_node_type( base ), "attribute" ) == 0 )                      // models.TextChoices → TextChoices
        {
            base = ts_node_child_by_field_name( base, "attribute", 9 );
            if( ts_node_is_null( base ) )
            {
                continue;
            }
        }
        if( std::strcmp( ts_node_type( base ), "identifier" ) != 0 )
        {
            continue;
        }
        const std::string_view baseName = nodeTextOf( base, src );
        if( baseName == "Enum" || baseName == "IntEnum" || baseName == "StrEnum"
         || baseName == "Flag" || baseName == "IntFlag" || baseName == "ReprEnum"
         || baseName == "Choices" || baseName == "TextChoices" || baseName == "IntegerChoices" )
        {
            return true;
        }
    }
    return false;
}
}   // namespace — ingest_names.h section of ingest.cpp

}   // namespace rw
