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
//
// The C++ `template` DISAMBIGUATOR is a KEYWORD, never part of a name. `X::template make<int>()` and
// `X::template Rebind<int>::f()` spell it in front of a dependent template name, and tree-sitter-cpp keeps it
// inside the dependent_name node whose TEXT the reference path reads. Returns `text` past one leading
// `template` token and the whitespace/comments after it, or `text` unchanged when it does not start with
// that token — the keyword must be followed by a separator, so `templateFn` stays a plain identifier.
// Measured before this existed (test/cppqualcheck.sh §12 (c)/(d)): `X::template tqDepQualTmpl<int>()` minted
// a reference NAMED `template tqDepQualTmpl`, which resolves to nothing, and
// `X::template TqRebind<int>::tqScopedFn()` keyed its qualifier as `template TqRebind`, so the canonical tier
// missed and the call split over a same-named decoy in another scope.
inline std::string_view skipTemplateDisambiguator( std::string_view text ) noexcept
{
    constexpr std::string_view kKeyword = "template";
    if( !text.starts_with( kKeyword ) )
    {
        return text;
    }
    std::string_view rest = text.substr( kKeyword.size() );
    while( !rest.empty() )
    {
        if( std::isspace( static_cast<unsigned char>( rest.front() ) ) )
        {
            rest.remove_prefix( 1 );
        }
        else if( rest.starts_with( "/*" ) )
        {
            const std::size_t close = rest.find( "*/", 2 );
            rest.remove_prefix( close == std::string_view::npos ? rest.size() : close + 2 );
        }
        else if( rest.starts_with( "//" ) )
        {
            const std::size_t eol = rest.find( '\n' );
            rest.remove_prefix( eol == std::string_view::npos ? rest.size() : eol + 1 );
        }
        else
        {
            break;
        }
    }
    const bool separated = rest.size() < text.size() - kKeyword.size();
    return separated && !rest.empty() ? rest : text;
}

inline std::string immediateScope( std::string_view full )
{
    const std::size_t cc = full.rfind( "::" );
    return std::string( skipTemplateDisambiguator( cc == std::string_view::npos ? full : full.substr( cc + 2 ) ) );
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
// VALID INPUT, not a corrupt invariant, so the capture loop simply skips it (never ASSUME, never
// DISCLOSE — nothing degraded). Query predicates cannot do this: passesPredicates is wired into
// --match/--lint only, not the tags pass (measured — a `#not-eq?` left --uses=static_cast at 165).
inline bool isCppCastKeyword( std::string_view name ) noexcept
{
    return name == "static_cast" || name == "reinterpret_cast" || name == "const_cast" || name == "dynamic_cast";
}

// #285: a JSX element invocation (`<Foo />`, `<Foo>…</Foo>`) is a call to Foo, exactly like `Foo()` —
// but tree-sitter's jsx_self_closing_element/jsx_opening_element `name:` field binds an (identifier)
// for BOTH a real component (`<Widget />`) and an intrinsic HTML/SVG tag (`<div>`, `<h1>`); the
// grammar carries no case distinction, so an intrinsic tag would otherwise mint a phantom call edge
// to a symbol that is never defined. react.dev's own rule is the filter: a user component's tag name
// MUST start with an uppercase letter for JSX to treat it as one rather than an HTML tag, so a
// lower-case-first-letter name at this shape is never a component. Query predicates cannot do this:
// passesPredicates is wired into --match/--lint only, not the tags pass (same measured fact
// isCppCastKeyword's note above relies on) — so, exactly like that cast filter, this is VALID INPUT,
// skipped at capture time, never ASSUME/DISCLOSE.
//
// Scope is deliberately narrow: only the bare-(identifier) shape is tested. A qualified tag
// (`<Foo.Bar />`) binds through a *different* tags.scm pattern (member_expression), never reaches
// this function, and is always kept — a property access is never mistaken for an intrinsic tag,
// upper-case or not, the same convention `Foo.Bar()` already gets as a plain member call. A
// namespaced tag (`<svg:rect />`) needs no test here at all: its name field is a distinct grammar
// node (jsx_namespace_name) that no tags.scm pattern names, so it never reaches captureTagsFacts as
// a reference in the first place — verified with `--match`, not assumed.
inline bool isJsxIntrinsicTagIdentifier( TSNode roleNode, TSNode nameNode, std::string_view name ) noexcept
{
    if( name.empty() || !kindIs( ts_node_type( nameNode ), "identifier" ) )
    {
        return false;
    }
    const char* roleType = ts_node_type( roleNode );
    if( !kindIs( roleType, "jsx_self_closing_element" ) && !kindIs( roleType, "jsx_opening_element" ) )
    {
        return false;
    }
    // Only an ASCII-lowercase first letter is an intrinsic tag (react.dev's own convention: anything else is
    // treated as a component). `_Widget` and `$Widget` start with legal, non-lowercase JS identifier
    // characters, so the old test (`!( c is uppercase )`) wrongly kept them as intrinsic; testing lower-case
    // directly keeps them — and any non-ASCII-letter name — as components instead.
    const unsigned char c = static_cast<unsigned char>( name.front() );
    return c >= 'a' && c <= 'z';
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
// DISCLOSE could truthfully claim. cppScopeNameText below walks the same chain under the same cap.
constexpr int kMaxQualifierHops = 32;   // `a::b::c::…` past 32 segments is not written C++
inline TSNode innermostQualifiedName( TSNode n ) noexcept
{
    for( int hop = 0; hop < kMaxQualifierHops; ++hop )
    {
        if( ts_node_is_null( n ) || !kindIs( ts_node_type( n ), "qualified_identifier" ) )
        {
            break;
        }
        const TSNode inner = fieldChild( n, NodeField::Name );
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

// ── C++ template scopes: the primary's member keys the template name, a specialization keeps its id ──────────
// A scope is half of an IDENTITY — the map's sc=, the canonical `path::scope::name` id the S6-C locality tie-break
// and the census key on, the `A::b` a selector names. tree-sitter-cpp hands a template scope over as a
// `template_type` (`name:` + `arguments:`) in three places: the `scope:` of a qualified declarator (`void
// Box<T>::grow()`), the `name:` of a class specialization (`struct Slot<bool> { … }`), and a link of a qualified
// class name (`struct Tree<T>::Leaf { … }`). Reading those nodes' raw TEXT made one member two identities — the
// in-class declaration `Box::grow` and the out-of-line body `Box<T>::grow` — so --callers=Box::grow resolved to the
// declaration and answered 0; a list broken over lines put the line break into the id; and `Slot<std::string>`,
// whose `::` sits INSIDE the list, was cut by immediateScope to `string>`.
//
// Two identities are genuinely different, and the reading keeps them apart (test/cpptmplscopecheck.sh):
//   * the PRIMARY template's own member — its declarator's template-id names exactly the parameters its own
//     `template <…>` introduces, `template <class T, int N> void Box<T, N>::grow()` — keys the bare name `Box`;
//   * a SPECIALIZATION (explicit or partial, a whole class or one member) keeps its template-id, spelled canonically
//     (canonicalTemplateIdText), because a call spelled `Traits<int>::encode( 1 )` names exactly that body and a
//     delegation from one specialization into another (`DenseMapInfo<APInt>::getHashValue` inside
//     `DenseMapInfo<APSInt>`) is a call to a different body. Joining them to the primary was measured on llvm ADT +
//     Support: 58 precise edges became splits and that delegation vanished.
// A REFERENCE keeps the template-id it writes; the resolver retries the template's family when no definition is keyed
// by it (resolve.h appendCanonicalCandidates).

inline bool isCppTemplateType( TSNode n ) noexcept
{
    return !ts_node_is_null( n ) && kindIs( ts_node_type( n ), "template_type" );
}

// Index just past a `//` or `/* */` comment starting at `i`, or `i` itself when none starts there. An unclosed comment
// runs to the end of `text`.
inline std::size_t cppCommentEnd( std::string_view text, std::size_t i ) noexcept
{
    if( text[i] != '/' || i + 1 >= text.size() || ( text[i + 1] != '/' && text[i + 1] != '*' ) )
    {
        return i;
    }
    const bool        lineComment = text[i + 1] == '/';
    const std::size_t close       = text.find( lineComment ? std::string_view( "\n" ) : std::string_view( "*/" ), i + 2 );
    return close == std::string_view::npos ? text.size() : close + ( lineComment ? 1 : 2 );
}

// One spelling for a template-id, so a definition and a call written differently still key one identity: whitespace
// and comments are dropped except for a single space between two identifier characters (`unsigned int`), and a comma
// is followed by one space. `Traits< int >` → "Traits<int>"; `Map<std::string,\n V>` → "Map<std::string, V>".
inline std::string canonicalTemplateIdText( std::string_view text )
{
    std::string canonical;
    canonical.reserve( text.size() );
    bool        separated = false;   // whitespace or a comment since the last kept character
    std::size_t i         = 0;
    while( i < text.size() )
    {
        const char        c         = text[i];
        const std::size_t afterSkip = std::isspace( static_cast<unsigned char>( c ) ) ? i + 1 : cppCommentEnd( text, i );
        if( afterSkip != i )
        {
            separated = true;
            i         = afterSkip;
            continue;
        }
        if( separated && !canonical.empty() && namesplit::isIdentChar( canonical.back() ) && namesplit::isIdentChar( c ) )
        {
            canonical.push_back( ' ' );
        }
        separated = false;
        canonical.push_back( c );
        if( c == ',' )
        {
            canonical.push_back( ' ' );
        }
        ++i;
    }
    return canonical;
}

// Where a template parameter's top-level default begins (its `=`), or `text.size()` when it has none. Angle,
// parenthesis, bracket and brace depth is tracked so `template <class U = int> class C` keeps its inner `=`.
inline std::size_t templateParameterDefaultStart( std::string_view text ) noexcept
{
    std::size_t depth = 0;
    for( std::size_t i = 0; i < text.size(); ++i )
    {
        const char c = text[i];
        if( c == '=' && depth == 0 )
        {
            return i;
        }
        const bool opens  = c == '<' || c == '(' || c == '[' || c == '{';
        const bool closes = c == '>' || c == ')' || c == ']' || c == '}';
        depth = opens ? depth + 1 : ( closes && depth > 0 ? depth - 1 : depth );
    }
    return text.size();
}

// The last identifier in `text`, or an empty view when it holds none.
inline std::string_view lastIdentifierIn( std::string_view text ) noexcept
{
    std::string_view last;
    std::size_t      i = 0;
    while( i < text.size() )
    {
        std::size_t runEnd = i;
        while( runEnd < text.size() && namesplit::isIdentChar( text[runEnd] ) )
        {
            ++runEnd;
        }
        if( runEnd > i && namesplit::isIdentStart( text[i] ) )
        {
            last = text.substr( i, runEnd - i );
        }
        i = runEnd > i ? runEnd : i + 1;
    }
    return last;
}

// The name one template parameter declares, read off its text: the last identifier before its top-level default `=`,
// with `...` appended for a pack — `class T` → "T", `int N = 4` → "N", `class... Ts` → "Ts...", `template <class U =
// int> class C` → "C". An unnamed parameter yields its keyword (`class`), which no template argument can equal.
inline std::string cppTemplateParameterName( std::string_view text )
{
    const std::string_view declared = text.substr( 0, templateParameterDefaultStart( text ) );
    std::string            name { lastIdentifierIn( declared ) };
    if( declared.find( "..." ) != std::string_view::npos )
    {
        name.append( "..." );
    }
    return name;
}

// True when `templateType`'s argument list names exactly the parameters `parameterList` declares, in order: the
// template-id a primary template's out-of-line member writes (`Box<T, N>` under `template <class T, int N>`).
inline bool templateIdNamesItsParameters( TSNode templateType, TSNode parameterList, std::string_view src )
{
    const TSNode arguments = fieldChild( templateType, NodeField::Arguments );
    if( ts_node_is_null( arguments ) || ts_node_is_null( parameterList ) )
    {
        return false;
    }
    const auto nextNamed = []( TSNode list, std::uint32_t index ) noexcept
    {
        const std::uint32_t count = ts_node_named_child_count( list );
        while( index < count && kindIs( ts_node_type( ts_node_named_child( list, index ) ), "comment" ) )
        {
            ++index;
        }
        return index;
    };
    const std::uint32_t argumentCount  = ts_node_named_child_count( arguments );
    const std::uint32_t parameterCount = ts_node_named_child_count( parameterList );
    std::uint32_t       a              = nextNamed( arguments, 0 );
    std::uint32_t       p              = nextNamed( parameterList, 0 );
    for( ; a < argumentCount && p < parameterCount; a = nextNamed( arguments, a + 1 ), p = nextNamed( parameterList, p + 1 ) )
    {
        const std::string argument = canonicalTemplateIdText( nodeTextOf( ts_node_named_child( arguments, a ), src ) );
        if( argument != cppTemplateParameterName( nodeTextOf( ts_node_named_child( parameterList, p ), src ) ) )
        {
            return false;
        }
    }
    return a >= argumentCount && p >= parameterCount && parameterCount > 0;
}

// The `template <…>` parameter lists that introduce the declaration `node` belongs to, INNERMOST first: the run of
// template_declaration ancestors directly above it. The walk passes through declarator and declaration wrappers and
// stops at the first body or namespace boundary, so nothing inside a function or class body reaches an enclosing
// template's list. On the way up it also counts the template-id `scope:` links of the qualified_identifier chain
// ABOVE `node` — the pairing index of `node`'s own scope. Stores at most kMaxQualifierHops lists — the chain cap, and
// past it only precision degrades.
struct TemplateParameterLists
{
    std::array<TSNode, static_cast<std::size_t>( kMaxQualifierHops )> innerFirst {};
    std::size_t                                                         count              = 0;
    std::size_t                                                         templateLinksAbove = 0;
};
inline TemplateParameterLists templateParameterListsAbove( TSNode node ) noexcept
{
    TemplateParameterLists lists;
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( kindIs( t, "qualified_identifier" ) )
        {
            lists.templateLinksAbove += isCppTemplateType( fieldChild( p, NodeField::Scope ) ) ? 1u : 0u;
            continue;
        }
        if( kindIs( t, "template_declaration" ) )
        {
            if( lists.count < lists.innerFirst.size() )
            {
                lists.innerFirst[ lists.count++ ] = fieldChild( p, NodeField::Parameters );
            }
            continue;
        }
        const bool boundary = kindIs( t, "compound_statement" ) || kindIs( t, "field_declaration_list" ) || kindIs( t, "declaration_list" )
                           || kindIs( t, "translation_unit" );
        if( lists.count > 0 || boundary )
        {
            break;
        }
    }
    return lists;
}

// How many `scope:` links of the qualified class name `name` are template-ids.
inline std::size_t templateScopeLinksIn( TSNode name ) noexcept
{
    std::size_t count = 0;
    for( int hop = 0; hop < kMaxQualifierHops && !ts_node_is_null( name ) && kindIs( ts_node_type( name ), "qualified_identifier" ); ++hop )
    {
        count += isCppTemplateType( fieldChild( name, NodeField::Scope ) ) ? 1u : 0u;
        name   = fieldChild( name, NodeField::Name );
    }
    return count;
}

// The scope text a DECLARATION's template-id link contributes: the bare template name when it is the primary's own
// id, its canonical template-id otherwise. The link is paired with the `template <…>` list that introduces it:
// outermost first when there are at least as many lists as template-id links (a member function template's own list
// is the extra, innermost one: `template <class T> template <class U> void Box<T>::convert( U )`), innermost first
// when there are fewer (the outer links then belong to an explicit specialization, which has no list of its own).
inline std::string cppDeclaratorLinkText( TSNode link, std::size_t linkIndex, std::size_t linkCount, const TemplateParameterLists& lists,
                                          std::string_view src )
{
    const std::size_t fromInner = lists.count >= linkCount ? lists.count - 1 - linkIndex : linkCount - 1 - linkIndex;
    if( fromInner < lists.count && templateIdNamesItsParameters( link, lists.innerFirst[ fromInner ], src ) )
    {
        return std::string( nodeFieldText( link, NodeField::Name, src ) );
    }
    return canonicalTemplateIdText( nodeTextOf( link, src ) );
}

// A class's written `name:` read as a scope. `struct Slot<bool>` is a specialization → "Slot<bool>";
// `template <class T> struct Tree<T>::Leaf` → "Tree::Leaf". A name with no template-id keeps its written text byte for
// byte — `Outer::Inner`, a Python class, a namespace — and a NULL `name` (an anonymous class) reads "".
inline std::string cppScopeNameText( TSNode name, std::string_view src )
{
    const std::string_view written = nodeTextOf( name, src );
    if( isCppTemplateType( name ) )
    {
        return canonicalTemplateIdText( written );
    }
    if( written.find( '<' ) == std::string_view::npos || !kindIs( ts_node_type( name ), "qualified_identifier" ) )
    {
        return std::string( written );
    }
    const std::size_t            linkCount = templateScopeLinksIn( name );
    const TemplateParameterLists lists     = templateParameterListsAbove( name );
    std::string                  scope;
    std::size_t                  linkIndex = 0;
    TSNode                       link      = name;
    for( int hop = 0; hop < kMaxQualifierHops && !ts_node_is_null( link ) && kindIs( ts_node_type( link ), "qualified_identifier" ); ++hop )
    {
        const TSNode segment = fieldChild( link, NodeField::Scope );             // null for a leading `::`
        scope.append( isCppTemplateType( segment ) ? cppDeclaratorLinkText( segment, linkIndex++, linkCount, lists, src )
                                                   : std::string( nodeTextOf( segment, src ) ) ).append( "::" );
        link = fieldChild( link, NodeField::Name );
    }
    return scope.append( canonicalTemplateIdText( nodeTextOf( link, src ) ) );
}

// A C++ class SPECIALIZATION header's base clause (`template <> struct Info<char> : CharBase {}`), captured by the tags
// query as @definition.specialization and never made a symbol. Each base becomes an inherit ref (captureBases) whose
// DERIVED name is the specialization's canonical template-id, carried in `qualifier` exactly as the Rust impl pass
// carries its implementor: byte-span attribution cannot name a derived class that is not a symbol. buildGraph's CHA
// name graph then knows what the specialization inherits (resolve.h appendCanonicalCandidates reads it); the Lego
// view resolves `qualifier` by symbol name and finds none, so its rows are unchanged.
// Returns true when the capture WAS a specialization header (and so must not continue to the definition path). The
// whole precondition is tested here rather than at the call site, which is captureTagsFacts: every branch spent there is
// measured (see cppDefNameReseat).
inline bool captureSpecializationHeader( bool isDef, Lang lang, std::string_view defCapture, TSNode classNode, TSNode nameNode, std::uint32_t fileId,
                                         std::string_view src, std::vector<RawRef>& refs )
{
    if( !isDef || lang != Lang::Cpp || defCapture != "definition.specialization" )
    {
        return false;
    }
    const std::size_t firstBase = refs.size();
    captureBases( classNode, fileId, Lang::Cpp, src, refs );
    const std::string derived = canonicalTemplateIdText( nodeTextOf( nameNode, src ) );
    for( std::size_t i = firstBase; i < refs.size(); ++i )
    {
        refs[i].qualifier = derived;
    }
    return true;
}

// The scope that qualifies `nameNode` — "" when it is unqualified, or qualified only by a separator error recovery
// invented (hasPhantomScopeSeparator). A plain scope reads its immediate segment (`a::B::c` → "B"). A template-id
// scope depends on who asks: a REFERENCE keeps the id it wrote, canonically (`Traits<int>::encode()` → "Traits<int>",
// never cut inside the list); a DEFINITION keys the bare name when the id is its primary template's own (`template
// <class T> void Box<T>::grow()` → "Box") and the canonical id otherwise (`template <> … Traits<long>::encode` →
// "Traits<long>"). An out-of-range span reads "", as before.
inline std::string cppQualifierText( TSNode nameNode, std::string_view src, bool isDefinition )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || !kindIs( ts_node_type( parent ), "qualified_identifier" ) || hasPhantomScopeSeparator( parent ) )
    {
        return {};
    }
    const TSNode scope = fieldChild( parent, NodeField::Scope );   // null for a leading `::`
    if( !isCppTemplateType( scope ) )
    {
        return immediateScope( nodeTextOf( scope, src ) );
    }
    if( !isDefinition )
    {
        return canonicalTemplateIdText( nodeTextOf( scope, src ) );
    }
    const TemplateParameterLists lists = templateParameterListsAbove( parent );   // `nameNode` is the chain's last link
    return cppDeclaratorLinkText( scope, lists.templateLinksAbove, lists.templateLinksAbove + 1, lists, src );
}
inline std::string qualifierOf( TSNode nameNode, std::string_view src )
{
    return cppQualifierText( nameNode, src, /*isDefinition=*/false );
}
inline std::string qualifierOfDefinition( TSNode nameNode, std::string_view src )
{
    return cppQualifierText( nameNode, src, /*isDefinition=*/true );
}

// #150 — NESTED std NAMESPACES. `qualifierOf`/`qualifierOfDefinition` above return only the IMMEDIATE scope
// segment ("ranges" for `std::ranges::move`), which cannot be told from a user's own `mylib::ranges::move`:
// that ambiguity is exactly the gap `keepStdQualifiedCandidates` (graph.h) could not close. These two
// helpers answer a different, narrower question — is the chain ROOTED in namespace std, at any depth? — by
// reading the FULL text tree-sitter already gives the outermost node, never by re-deriving it from the
// (already-truncated) immediate qualifier.
//
// `nameNode` here is always the SAME @name node qualifierOf/qualifierOfDefinition read: for a call, the tags
// query capture (queries/cpp/tags.scm's "QUALIFIED CALLS AT ANY DEPTH" pattern); for an out-of-line
// definition, the definition pattern's own @name. tree-sitter-cpp nests qualified_identifier
// RIGHT-recursively — `A::B::C` is qualified_identifier(scope: A, name: qualified_identifier(scope: B, name:
// C)) — and that outermost node's own TEXT SPAN is the entire chain exactly as written, leading `::`
// included, so reading only its first segment is safe with a plain `find` (never the template-aware
// last-segment scanners used elsewhere in this file): nothing can appear before a call's own root, template
// arguments included — a template argument list is always part of a LATER segment, never a prefix of the
// first one.
//
// `ts_node_parent( nameNode )` reaches that OUTERMOST node directly for a CALL (queries/cpp/tags.scm's call
// pattern captures @name at the call's own `function:` field, one hop from the outermost identifier — see
// its "QUALIFIED CALLS AT ANY DEPTH" comment). It does NOT for a 3+-segment OUT-OF-LINE DEFINITION: ingest.cpp
// re-seats a definition's @name to the INNERMOST link of the chain (queries/cpp/tags.scm's own comment on the
// method pattern: "ingest.cpp descends it to the innermost name:" — cppDefNameReseat), so `std::detail::f`'s
// nameNode there is `f` and its immediate parent is only the INNER `detail::f` node, not the outer
// `std::detail::f` one. Found by review (redhat-et/ripwire #150, adversarial pass 2026-09-23): the prior
// version of this function trusted `ts_node_parent` alone and read "detail" as the root, wrongly refusing a
// real std-rooted out-of-line definition. The climb below walks OUTWARD through every further
// qualified_identifier ancestor (a no-op for a call — its outermost node's own parent is a call_expression,
// never another qualified_identifier, so the loop tests once and stops) until nothing higher is still part of
// the chain, and reads the root from THAT node's text instead.
// The written chain's first segment, and whether it was written from the global scope (`::std::…`); nullopt when
// nameNode is not the name of a (well-formed) qualified_identifier. The root test below reads `root` alone;
// cppDefinitionRootsStd also reads `global`, so both answers come from the ONE climb.
struct CppWrittenChainRoot
{
    std::string_view root;
    bool             global = false;
};
inline std::optional<CppWrittenChainRoot> cppWrittenChainRoot( TSNode nameNode, std::string_view src )
{
    TSNode outer = ts_node_parent( nameNode );
    if( ts_node_is_null( outer ) || !kindIs( ts_node_type( outer ), "qualified_identifier" ) || hasPhantomScopeSeparator( outer ) )
    {
        return std::nullopt;
    }
    for( TSNode up = ts_node_parent( outer ); !ts_node_is_null( up ) && kindIs( ts_node_type( up ), "qualified_identifier" ); up = ts_node_parent( up ) )
    {
        outer = up;
    }
    std::string_view text   = nodeTextOf( outer, src );
    const bool       global = text.starts_with( "::" );
    if( global )
    {
        text.remove_prefix( 2 );   // `::std::move` — the leading global-scope operator names no segment
    }
    const std::size_t sep = text.find( "::" );
    return CppWrittenChainRoot{ sep == std::string_view::npos ? text : text.substr( 0, sep ), global };
}

inline bool cppQualifiedChainRootsStd( TSNode nameNode, std::string_view src )
{
    const std::optional<CppWrittenChainRoot> written = cppWrittenChainRoot( nameNode, src );
    return written.has_value() && written->root == "std";
}

// The definition-side twin for an IN-CLASS / in-namespace def (`namespace std { namespace ranges { … } }`,
// or the C++17 nested spelling `namespace std::ranges { … }`) — the shape `cppQualifiedChainRootsStd` above
// does not reach, because such a def's @name node is never the `name:` field of a qualified_identifier at
// all. Walks EVERY enclosing namespace_definition out to the translation unit — not just the nearest one
// enclosingScopeOf reads — because a class sitting inside std must not stop the walk: `namespace std {
// struct Pair { auto first() {…} } }` needs `first`'s chain walked THROUGH Pair to reach std. Each
// namespace level's OWN `name:` text is read for only its FIRST written segment, so `namespace std::ranges {
// … }` (whichever way the grammar nests that C++17 spelling) and `namespace std { namespace ranges { … } }`
// answer identically. An anonymous namespace (`namespace { … }`, `name:` null) is transparent — the walk
// continues through it unchanged. The LAST namespace level found while climbing (i.e. the OUTERMOST one) is
// what decides the answer, which is why `namespace mylib { namespace std { … } }` is correctly NOT
// std-rooted: the outermost level there is "mylib", and the language itself permits reopening the real
// `::std` only at file scope ([namespace.std]), never nested inside another namespace.
// The first written segment of the OUTERMOST named namespace enclosing `node`, or nullopt when no named namespace
// encloses it (anonymous ones are transparent). cppEnclosingChainRootsStd asks whether it is "std";
// cppDefinitionRootsStd asks only whether there is one.
inline std::optional<std::string_view> cppOutermostNamedNamespaceRoot( TSNode node, std::string_view src )
{
    std::string_view outermostNsRoot;
    bool              sawNamespace = false;
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( !kindIs( ts_node_type( p ), "namespace_definition" ) )
        {
            continue;
        }
        const TSNode nm = fieldChild( p, NodeField::Name );
        if( ts_node_is_null( nm ) )
        {
            continue;   // anonymous namespace — transparent, keep climbing
        }
        const std::string_view text = nodeTextOf( nm, src );
        const std::size_t      sep  = text.find( "::" );
        outermostNsRoot = sep == std::string_view::npos ? text : text.substr( 0, sep );
        sawNamespace    = true;
    }
    return sawNamespace ? std::optional<std::string_view>( outermostNsRoot ) : std::nullopt;
}

inline bool cppEnclosingChainRootsStd( TSNode node, std::string_view src )
{
    return cppOutermostNamedNamespaceRoot( node, src ) == std::optional<std::string_view>( "std" );
}

// A WRITTEN `std::` qualifier is resolved against where the def sits (CodeRabbit on #331). A qualified definition
// names an entity of a namespace that ENCLOSES it ([namespace.memdef]), so `void std::ranges::f() {}` written inside
// `namespace vendor { … }` defines `vendor::std::ranges::f` — the real `::std` can only be re-opened out of line at
// file scope. Such a def used to be marked std-rooted anyway, and keepStdQualifiedCandidates could then keep it as the
// target of a call to the real `std::ranges::f`: a false edge to a same-spelled def. So the qualified test holds only
// when no NAMED namespace encloses the def (an anonymous one stays transparent, as in the walk above) or the chain is
// written from the global scope (`::std::…`); every other case falls to the enclosing walk, whose outermost-root rule
// already answers `vendor` there.
// The definition-side dispatcher: an out-of-line qualified def (`std::SomeType::f() {…}`, rare but legal —
// re-opening a std entity out of line) is std-rooted exactly as a CALL with the same written chain would be,
// so it tries cppQualifiedChainRootsStd first. OR, not either/or (found by the same review pass as the climb
// above): a def can be qualified AND still need the enclosing-namespace walk — `namespace std { int
// detail::innerHelper(int) {} }` writes only the PARTIAL qualifier `detail::innerHelper` at the declarator
// (chain root "detail", not "std"), and the real answer lives in the surrounding `namespace std { … }` block
// the qualified check never looks at. Every def shape that is std-rooted at all is std-rooted by exactly one
// of the two tests — a bare in-class/in-namespace def only ever reaches the enclosing walk (its declarator is
// never a qualified_identifier, so the qualified check is a cheap, safe false) — so this is never redundant
// work pretending to be a belt-and-suspenders check.
inline bool cppDefinitionRootsStd( TSNode nameNode, std::string_view src )
{
    const std::optional<CppWrittenChainRoot> written = cppWrittenChainRoot( nameNode, src );
    if( written.has_value() && written->root == "std"
        && ( written->global || !cppOutermostNamedNamespaceRoot( nameNode, src ).has_value() ) )
    {
        return true;
    }
    return cppEnclosingChainRootsStd( nameNode, src );   // also `namespace std { int detail::f() {} }` (partial qualifier)
}

// The qualifier the 3+-segment re-split keys a REFERENCE on, from the scope half of its captured text: the last
// top-level segment, a template-id kept whole and canonical (`numeric_limits<std::size_t>` stays itself; the resolver
// falls back to the family when nothing is keyed by it). PRECONDITION: `scopeText` holds no operator tail — it is the
// part BEFORE the name's separator, and an operator never names a scope.
inline std::string cppRefQualifierText( std::string_view scopeText )
{
    const std::size_t      sep  = lastTopLevelScopeSep( scopeText );
    const std::string_view last = skipTemplateDisambiguator( sep == std::string_view::npos ? scopeText : scopeText.substr( sep + 2 ) );
    return last.ends_with( '>' ) ? canonicalTemplateIdText( last ) : immediateScope( last );
}

// H4 RE-SPLIT of a C++ call reference's (name, qualifier), moved out of captureTagsFacts (whose complexity is
// measured). The widened qualified-call pattern binds the INNER node, so a 3+-segment call's captured text
// still carries scope (`inner::targetFn`). Recover the pair the canonical tier keys on — name = the final
// segment, qualifier = the IMMEDIATE scope — from the text itself. This must run AFTER the reference's
// finalSegment() name and qualifierOf() qualifier are set, and overwrites both when it splits: finalSegment
// truncates at the first '<', which would name `numeric_limits<std::size_t>::max` as `numeric_limits` and mint
// an edge to the wrong symbol. Inert for every 2-segment call (`rw::midFn` binds a bare identifier — no
// top-level `::` in the text) and for `ns::tmplFn<int>()` (whose captured text is just `tmplFn<int>`), so
// those keep their qualifierOf() result untouched.
//
// An OPERATOR tail is recognised first: its `<`/`>` are part of the NAME, so handing it to the angle-depth
// scan binds the wrong scope for the whole `>` family. See operatorNameStart. When the operator spelling
// starts at index 0 the capture IS the bare operator name, its parent is the qualified_identifier, and
// qualifierOf() already put the immediate scope in r.qualifier — nothing to re-split.
//
// The `template` disambiguator (see skipTemplateDisambiguator) is stepped over on the NAME half here — at
// 2 segments too, where the capture is the dependent_name itself (`template make<int>`) and nothing splits —
// and on the QUALIFIER half inside immediateScope.
inline void cppResplitRefName( RawRef& r, std::string_view nameTxt )
{
    const std::size_t opStart  = operatorNameStart( nameTxt );
    const bool        opScoped = opStart != std::string_view::npos && opStart >= 2 && nameTxt[ opStart - 1 ] == ':' && nameTxt[ opStart - 2 ] == ':';
    if( opScoped )
    {
        r.name      = finalSegment( nameTxt.substr( opStart ) );                                  // `operator>` verbatim
        r.qualifier = cppRefQualifierText( nameTxt.substr( 0, opStart - 2 ) );
        return;
    }
    if( opStart != std::string_view::npos )
    {
        return;
    }
    const std::size_t      sep    = lastTopLevelScopeSep( nameTxt );
    const bool             hasSep = sep != std::string_view::npos;
    const std::string_view tail   = hasSep ? nameTxt.substr( sep + 2 ) : nameTxt;
    const std::string_view bare   = skipTemplateDisambiguator( tail );
    if( hasSep || bare.size() != tail.size() )   // neither a split nor a keyword: finalSegment( nameTxt ) already named it
    {
        r.name = finalSegment( bare );
    }
    if( hasSep )
    {
        r.qualifier = cppRefQualifierText( nameTxt.substr( 0, sep ) );
    }
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
        const bool  isImpl  = kindIs( t, "impl_item" );
        const bool  isTrait = kindIs( t, "trait_item" );
        const bool  isMod   = includeModules && kindIs( t, "mod_item" );
        if( !isImpl && !isTrait && !isMod )
        {
            continue;
        }

        // impl carries the implementor under `type:`; trait/mod carry their own `name:`. Anonymous/ill-formed
        // (empty text) yields "" — no usable scope — which is the same degrade as "no owner above".
        const TSNode owner = isImpl ? fieldChild( p, NodeField::Type ) : fieldChild( p, NodeField::Name );
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
    if( ts_node_is_null( parent ) || !kindIs( ts_node_type( parent ), "scoped_identifier" ) )
    {
        return {};
    }

    std::string qualifier = rustPathSegment( nodeTextOf( fieldChild( parent, NodeField::Path ), src ) );
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
        const bool scopeOwner =    kindIs( t, "class_specifier" ) || kindIs( t, "struct_specifier" )
                                || kindIs( t, "namespace_definition" ) || kindIs( t, "class_definition" );
        if( scopeOwner )
        {
            // `struct Slot<bool>` → "Slot"; every non-template name keeps its written text; anonymous (no `name:`) → ""
            return cppScopeNameText( fieldChild( p, NodeField::Name ), src );
        }
    }
    return {};
}

// Kotlin: the enclosing class/object/companion-object of a definition. Not folded into the shared
// enclosingScopeOf for two reasons, each sufficient alone. (1) Its scope-owner kinds carry NO `name:`
// field in this grammar — class_declaration/object_declaration/companion_object expose the name only as
// a positional `type_identifier` child — so the shared walker's field lookup would read "no scope" on
// every call rather than fail loudly. (2) `class_declaration` is also a node kind in the Java, C#,
// TypeScript and Swift grammars, WITH a `name:` field there, so listing it in the shared walker would
// silently start scoping those languages' definitions too — Ruby's bare-word collision argument (below)
// in a different spelling. Anonymous companion objects (`companion object { ... }`) have no
// type_identifier child and are walked THROUGH, exactly like Ruby's `class << self` singleton_class,
// so a member of one scopes to the class that owns it.
inline std::string kotlinEnclosingScopeOf( TSNode nameNode, std::string_view src )
{
    for( TSNode p = ts_node_parent( nameNode ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        const bool scopeOwner =    kindIs( t, "class_declaration" )
                                 || kindIs( t, "object_declaration" )
                                 || kindIs( t, "companion_object" );
        if( !scopeOwner )
        {
            continue;
        }
        const TSNode nm = firstChildOfType( p, "type_identifier" );
        if( ts_node_is_null( nm ) || ts_node_eq( nm, nameNode ) )
        {
            continue;   // anonymous companion object (walk through to whatever encloses IT), OR this
                         // IS the definition being scoped (its scope is what encloses it) — same outcome
        }
        return std::string( nodeTextOf( nm, src ) );
    }
    return {};
}

// Ruby: the enclosing `class` / `module` of a definition — the Ruby arm of the P2-D Rule-1 scope that
// enclosingScopeOf gives C++ and Python. Kept separate rather than folded into enclosingScopeOf because
// tree-sitter-ruby's kinds are bare words (`class`, `module`) that several other grammars also spell — JS
// has a named `class` expression — and enclosingScopeOf is shared; a Ruby-only walker cannot collide.
// Three shapes the shared walker would get wrong (every one pinned by test/rubyscopecheck.sh):
//   * `class << self … end` is a `singleton_class` with NO name field — it is walked THROUGH, so a def
//     inside it scopes to the class that owns the singleton (the reading `def self.m` already gets);
//   * the definition's OWN node is skipped — `class Widget` inside `module Outer` scopes to "Outer", not
//     to itself (enclosingScopeOf's Python arm does report a class as its own scope; that quirk is not
//     copied here — a scope is what ENCLOSES a def);
//   * `class Foo::Bar` names itself with a scope_resolution — the IMMEDIATE scope is its final segment
//     ("Bar"), the same contract C++'s qualifierOf keeps for `A::B::m`.
// Returns "" at file level, so a top-level `def` keeps no scope and no id= (the file is not a scope).
inline std::string rubyEnclosingScopeOf( TSNode nameNode, std::string_view src )
{
    for( TSNode p = ts_node_parent( nameNode ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( !kindIs( t, "class" ) && !kindIs( t, "module" ) )
        {
            continue;
        }
        TSNode nm = fieldChild( p, NodeField::Name );
        if( ts_node_is_null( nm ) )
        {
            return {};   // anonymous → no usable scope (the grammar always names these; guard, don't assert)
        }
        if( ts_node_eq( nm, nameNode ) )
        {
            continue;    // this IS the definition being scoped — its scope is what encloses it
        }
        if( kindIs( ts_node_type( nm ), "scope_resolution" ) )
        {
            const TSNode last = fieldChild( nm, NodeField::Name );
            if( !ts_node_is_null( last ) )
            {
                nm = last;
            }
        }
        const std::uint32_t a = ts_node_start_byte( nm ), b = ts_node_end_byte( nm );
        return ( a <= b && b <= src.size() ) ? std::string( src.substr( a, b - a ) ) : std::string{};
    }
    return {};
}

// Ruby: is this captured call name the METHOD of a (call) that is the `left:` field of an (assignment)?
// `obj.name = v` parses to (assignment left: (call receiver: … method: (identifier))) — the SAME (call)
// shape as the read `obj.name`, so queries/ruby/tags.scm's call rule captures both and only the parent
// tells them apart. True ⇒ the site calls the setter `name=`. Deliberately plain `assignment` only: an
// `operator_assignment` (`obj.count += 1`, `obj.count ||= 1`) reads AND writes, and one capture carries one
// name — it keeps the getter edge, a floor test/rubysettercheck.sh pins. A `left_assignment_list`
// (`a.x, b.y = 1, 2`) wraps its targets one level deeper and is not read here either (same gate, same
// reason). The receiver's DEPTH is irrelevant on purpose — `obj.inner.name = v` is still an (assignment)
// whose `left:` is the outer (call), so it renames too; and the explicit call spelling `obj.name=(v)` is
// the same (assignment) node to this grammar, so it needs no separate arm. Both are gated.
inline bool rubyCallIsAssignmentTarget( TSNode nameNode ) noexcept
{
    const TSNode call = ts_node_parent( nameNode );
    if( ts_node_is_null( call ) || !kindIs( ts_node_type( call ), "call" ) )
    {
        return false;
    }
    const TSNode assign = ts_node_parent( call );
    if( ts_node_is_null( assign ) || !kindIs( ts_node_type( assign ), "assignment" ) )
    {
        return false;
    }
    const TSNode left = fieldChild( assign, NodeField::Left );
    return !ts_node_is_null( left ) && ts_node_eq( left, call );
}

// Parser version 121 (test/rubyattrscheck.sh): Ruby's class-level attribute DSL DEFINES symbols. The getter's
// nameByte rides the symbol's first TEXT byte (after the ':'), the setter's the token's first byte (the ':'):
// both stay inside [startByte, endByte) — the extentsuspect R1 head rule — and the two defs of one token can
// never collide with each other or with another token's pair (tokens never overlap and every simple_symbol is
// ≥ 2 bytes), so both survive dedupRawDefs' (fileId, nameByte) identity. Placed here rather than in
// captureIncludes because it mints DEFS: called from captureTagsFacts it lands inside the same per-file defs
// window the tags pass writes, so warm lex and the cache round-trip treat it exactly like any other captured
// def. The walk is the same iterative pre-order captureIncludes uses — explicit stack, no recursion, source
// order preserved (byte-identity determinism).
//
// Per-call emitter: one Var def per simple_symbol argument (the name minus the leading ':'), plus the `<x>=`
// setter where the family spells writers — attr_writer/accessor/attribute; attr_reader (getter only) and the
// plural `attributes` (third-party DSLs measured readers-only: AMS, jsonapi-serializer, dry-struct) spell no
// setter. Keyword args (`default:`, a type) and non-symbol args are data, not defs: the singular
// `attribute` stops at its first argument (a comment before it is skipped, it is no argument). defs come ONLY from the call's own argument_list — a do-block
// body is not one of the call's fields, so a block body can never leak defs.
inline void captureRubyAttrDefsCall( TSNode n, std::uint32_t fileId, std::string_view src,
                                     std::string_view fam, std::vector<RawDef>& defs )
{
    const TSNode args = fieldChild( n, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        return;
    }
    const bool reader        = fam != "attr_writer";
    const bool writer        = fam != "attr_reader" && fam != "attributes";   // plural `attributes` is readers-only (measured: AMS / jsonapi-serializer / dry-struct define no setters)
    const bool firstNameOnly = fam == "attribute";   // trailing type/metadata args are data, not defs
    ChildCursor ac( args );
    forEachNamedChild( args, ac.cur, [ & ]( TSNode a )
    {
        if( ts_node_is_extra( a ) )
        {
            return true;   // a comment is a named child too (`attribute( # note` then `:name )`); it is no argument
        }
        if( !kindIs( ts_node_type( a ), "simple_symbol" ) )
        {
            return !firstNameOnly;   // a non-symbol argument: the singular stops at its first arg whatever it is
        }
        std::string_view txt = nodeTextOf( a, src );
        if( !txt.empty() && txt.front() == ':' )
        {
            txt.remove_prefix( 1 );
        }
        if( txt.empty() )
        {
            return !firstNameOnly;   // defensive: an empty symbol text is no name; same first-arg stop as any non-symbol
        }
        const std::uint32_t s = ts_node_start_byte( a );
        RawDef d;
        d.fileId = fileId; d.line = ts_node_start_point( a ).row + 1; d.startByte = s; d.endByte = ts_node_end_byte( a );
        d.loc = 1; d.kind = SymKind::Var; d.lang = Lang::Ruby; d.scope = rubyEnclosingScopeOf( a, src );
        if( reader )
        {
            d.nameByte = s + 1; d.name = txt; defs.push_back( d );
        }
        if( writer )
        {
            d.nameByte = s; d.name = std::string( txt ) + '='; defs.push_back( std::move( d ) );
        }
        return !firstNameOnly;   // `attribute :x, :decimal, …`: stop at the first named child (unknown spellings there define nothing)
    } );
}

inline void captureRubyAttrDefs( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawDef>& defs )
{
    if( src.find( "attr" ) == std::string_view::npos )   // file signal: every family name contains "attr"
    {
        return;
    }
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    std::vector<TSNode> stack;
    stack.reserve( 64 );
    collectChildren( root, cursor.cur, kids );   // root's width is file-controlled — never index it (O(C²))
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( kids[i - 1] );
    }
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        if( kindIs( ts_node_type( n ), "call" ) )
        {
            const std::string_view fam = rubyNamedDirective( n, src, kRubyAttrFamilyNames );
            if( !fam.empty() && rubyAttrAtClassBodyLevel( n, src ) )
            {
                captureRubyAttrDefsCall( n, fileId, src, fam, defs );
            }
        }
        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( kids[i - 1] );
        }
    }
}


// ─── parser version 122 (test/rubyschemacheck.sh): RUBY db/schema.rb COLUMNS ARE Section DEFS ───
// A schema file is recognized BY CONTENT, never by path: any Ruby file whose tree holds a
// `create_table "x", … do |t| … end` call — the call's `block:` field is a do_block whose `parameters:`
// field is a block_parameters carrying ONE bare identifier — is a rendered-schema document (the block
// is the create_table call's OWN do_block, found by named-child kind because the shared NodeField set
// has no Block enumerator). Path plays no part: a schema dumped inside `ActiveRecord::Schema[8.1]
// .define … do`, a migration's class-level table, or a plain top-level one all look identical to this
// walk — the container does not matter. The file signal below is a contains-"create_table" reject like
// the attribute-family capture's contains-"attr" reject; the semantic gate is the AST shape.
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
inline constexpr std::array<std::string_view, 4> kRubySchemaNonColumns = { "index", "references", "belongs_to", "polymorphic" };

// The FIRST non-comment named child of an argument_list — the attribute-DSL comment posture ("attribute( # note
// then :x"): a comment is an n-ary extra, never an argument. Null when the list is all comments/empty.
inline TSNode rubyFirstNonCommentArg( TSNode args, std::string_view /*src*/ ) noexcept
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
    const TSNode nameNode = rubyFirstNonCommentArg( args, src );
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

// One create_table call: the schema-file gate plus the whole table's defs (name, options, columns, id).
inline void rubySchemaTableCall( TSNode n, std::uint32_t fileId, std::string_view src, std::vector<RawDef>& defs )
{
    std::string_view receiverName;   // the block parameter's name (`t`); empty until Gate 2 passes
    // Gate 0: a rendered schema's tables live at file level or under `ActiveRecord::Schema[].define … do`
    // — NEVER inside a class/module body. A MIGRATION's `create_table "users" … do |t|` (class-wrapped,
    // often string-named) is the same AST shape, and without this gate it would mint the SAME columns as
    // the schema that migration created — double-counting every added column on every corpus with both
    // files indexed. `add_column`/`remove_column` are not read anywhere (a column added then dropped never
    // registers; pinned by the migration fixtures), but the create_table of a real migration must not
    // double its schema either. Excluding at least one `class`/`module` ancestor keeps the capture
    // content-gated (still no path heuristic): a migration file next to the schema contributes ZERO defs.
    // Checked FIRST — the cheapest gate — before the argument/block walks.
    {
        for( TSNode p = ts_node_parent( n ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
        {
            const std::string_view k( ts_node_type( p ) );
            if( k == "class" || k == "module" )   // a locals distilled walk — no cross-helper dependency
            {
                return;
            }
        }
    }
    const TSNode args = fieldChild( n, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        return;
    }
    // Gate 1: a STRING table name as the first argument (a symbol-named table is a migration spelling,
    // not a rendered-schema shape — stated floor; no name node → no schema surface either).
    const TSNode tableName = rubyFirstNonCommentArg( args, src );
    if( ts_node_is_null( tableName ) || !kindIs( ts_node_type( tableName ), "string" ) )
    {
        return;
    }
    // Gate 2: the call's OWN do_block, and its parameters: field carries ONE bare identifier (the `|t|`).
    TSNode block{};
    {
        ChildCursor cursor( n );
        forEachNamedChild( n, cursor.cur, [ & ]( TSNode c )
        {
            if( kindIs( ts_node_type( c ), "do_block" ) )
            {
                block = c;
                return false;
            }
            return true;
        } );
    }
    if( ts_node_is_null( block ) )
    {
        return;
    }
    const TSNode params = fieldChild( block, NodeField::Parameters );
    if( ts_node_is_null( params ) )
    {
        return;   // `create_table "x" do … end` with no handle — not the schema shape
    }
    {
        ChildCursor cursor( params );
        TSNode      only{};
        std::size_t named = 0;
        forEachNamedChild( params, cursor.cur, [ & ]( TSNode c ) { only = c; ++named; return true; } );
        if( named != 1 || !kindIs( ts_node_type( only ), "identifier" ) )
        {
            return;   // multi-parameter or non-identifier handle — not a rendered schema's do |t|
        }
        receiverName = nodeTextOf( only, src );   // the `|t|` spelling — column calls must use it
    }
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
    // Implicit `id` — anchored at the table-name string's content start (a stable per-table byte).
    {
        const std::uint32_t s = ts_node_start_byte( tableName ), e = ts_node_end_byte( tableName );
        RawDef d;
        d.fileId = fileId; d.line = ts_node_start_point( tableName ).row + 1; d.startByte = s; d.endByte = e; d.loc = 1;
        d.kind = SymKind::Section; d.lang = Lang::Ruby; d.nameByte = s + 1; d.name = "id";
        defs.push_back( d );
    }
}

// The schema walk: ONE pass over the whole tree (the same explicit-stack shape as captureRubyAttrDefs —
// root's width is file-controlled, never index it, O(C²)). Every create_table-with-handle call in the
// file mints its table's defs; anything that is not such a call contributes nothing.
inline void captureRubySchemaDefs( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawDef>& defs )
{
    if( src.find( "create_table" ) == std::string_view::npos )   // file signal: the gate name must appear
    {
        return;
    }
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    std::vector<TSNode> stack;
    stack.reserve( 64 );
    collectChildren( root, cursor.cur, kids );   // root's width is file-controlled — never index it (O(C²))
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( kids[i - 1] );
    }
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        if( kindIs( ts_node_type( n ), "call" ) && fieldIdentifierText( n, NodeField::Method, src ) == "create_table" )
        {
            rubySchemaTableCall( n, fileId, src, defs );
        }
        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( kids[i - 1] );
        }
    }
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
// Which kind of scope owner an ancestor walk from `node` reaches FIRST: true for one of `inside`, false for one of `outside`
// (or neither, at the root). The one walk behind "is this declaration local to an executable body" for every grammar that
// asks it — Swift's local binding below and C++'s block-scope direct-initialized local (cppBlockScopeDirectInit).
inline bool nearestScopeOwnerIs( TSNode node, std::initializer_list<std::string_view> inside, std::initializer_list<std::string_view> outside ) noexcept
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const std::string_view kind( ts_node_type( p ) );
        if( std::find( inside.begin(), inside.end(), kind ) != inside.end() )
        {
            return true;
        }
        if( std::find( outside.begin(), outside.end(), kind ) != outside.end() )
        {
            return false;
        }
    }
    return false;
}

inline bool isSwiftLocalBinding( TSNode declNode ) noexcept
{
    // inside an executable block → local binding; a member property's wrappers reached first → NOT a local
    return nearestScopeOwnerIs( declNode, { "statements" }, { "class_body", "enum_class_body", "protocol_body", "source_file" } );
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
        if( kindIs( t, "attribute_item" ) )
        {
            // O(children): `#[ /*…*/ test ]` puts the comments in the attribute_item — 56x at 16 000
            // (test/childwalkscalecheck.sh, arm B23). The sibling climb this sits in is a different scan:
            // ts_node_prev_sibling restarts from the parent's first child too (the parent-chain family).
            bool        marked = false;
            ChildCursor cursor( prev );
            forEachChild( prev, cursor.cur, [ & ]( TSNode ch )
            {
                marked = kindIs( ts_node_type( ch ), "attribute" ) && rustAttrIsTestMarker( nodeTextOf( ch, src ) );
                return !marked;
            } );
            if( marked )
            {
                return true;
            }
            continue;
        }
        if( kindIs( t, "line_comment" ) || kindIs( t, "block_comment" ) )
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
    // O(children) at both levels — and this runs on every ANCESTOR of a def (anySelfOrAncestor), so the
    // declaration_list and the compilation_unit scan their whole child lists too: `public /*…*/ void M()`
    // measured 37x its control at 16 000 comments (test/childwalkscalecheck.sh, arm B24). Two cursors:
    // the attribute_list walk runs while the declaration walk is mid-iteration.
    bool        marked = false;
    ChildCursor lists( n );
    ChildCursor attrs( n );
    forEachChild( n, lists.cur, [ & ]( TSNode list )
    {
        if( !kindIs( ts_node_type( list ), "attribute_list" ) )
        {
            return true;
        }
        forEachChild( list, attrs.cur, [ & ]( TSNode attr )
        {
            marked =    kindIs( ts_node_type( attr ), "attribute" )
                     && csharpAttrIsTestMarker( nodeTextOf( fieldChild( attr, NodeField::Name ), src ) );
            return !marked;
        } );
        return !marked;
    } );
    return marked;
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
        if( !kindIs( ts_node_type( n ), "class_definition" ) )
        {
            continue;
        }
        if( pyTestClassName( nodeTextOf( fieldChild( n, NodeField::Name ), src ) ) )
        {
            return true;    // a member of a Test* class, at any nesting depth
        }
        enclosedByClass = true;
    }
    if( enclosedByClass || !kindIs( ts_node_type( defNode ), "function_definition" ) )
    {
        return false;
    }
    return nodeTextOf( fieldChild( defNode, NodeField::Name ), src ).rfind( "test_", 0 ) == 0;
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

// The `recovered` extraction bit (RawDef::recovered; extentsuspect.h rule `error`). Two shapes, both measured on the
// scope-leak fixture family (test/extentfix): a CLASS whose own body holds an error while an ERROR node encloses it —
// the struct whose body swallowed the definitions after it — and a C++ `method` with NO scope inside an ERROR node — a
// member of a class the recovery dissolved (a field_identifier declarator only exists inside a class body). A clean
// class inside a recovered file is NOT marked: its body parsed, so its members' scope is the one the source gave them.
// The ancestor walk (anySelfOrAncestor, above) runs only for those rare candidates, in a file whose root has an error.
inline std::uint8_t parseRecoveredBits( TSNode defNode, SymKind kind, Lang lang, bool isScopeless )
{
    const bool isContainerShape = extent::inSet( extent::kExtentClassKinds, kind ) && ts_node_has_error( defNode );
    const bool isOrphanShape    = lang == Lang::Cpp && kind == SymKind::Method && isScopeless;
    if( !isContainerShape && !isOrphanShape )
    {
        return 0;
    }
    const bool hasErrorAncestor = anySelfOrAncestor( ts_node_parent( defNode ), []( TSNode n ) noexcept { return ts_node_is_error( n ); } );
    if( !hasErrorAncestor )
    {
        return 0;
    }
    return isContainerShape ? extent::kRecoveredContainer : extent::kRecoveredOrphan;
}

// Rust: the def itself, or any enclosing `mod`/`fn`, carries a test attribute.
inline bool rustInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept
                                       {
                                           const char* t = ts_node_type( n );
                                           return    ( kindIs( t, "mod_item" ) || kindIs( t, "function_item" ) )
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
                                           if( !kindIs( ts_node_type( n ), "call_expression" ) )
                                           {
                                               return false;
                                           }
                                           const std::string_view callee = nodeTextOf( fieldChild( n, NodeField::Function ), src );
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
    if( ts_node_is_null( exprStmtNode ) || !kindIs( ts_node_type( exprStmtNode ), "expression_statement" ) )
    {
        return {};
    }

    // the MISSING ";" — the one structural mark separating a macro-with-block from a real statement.
    // O(children): the recovered expression_statement owns every comment between `)` and the block —
    // 16 000 of them measured 29x the identical flood after the block (childwalkscalecheck B26)
    bool        hasMissingSemicolon = false;
    ChildCursor cursor( exprStmtNode );
    forEachChild( exprStmtNode, cursor.cur, [ & ]( TSNode c ) { hasMissingSemicolon = ts_node_is_missing( c ); return !hasMissingSemicolon; } );
    if( !hasMissingSemicolon )
    {
        return {};
    }

    const TSNode body = ts_node_next_named_sibling( exprStmtNode );
    if( ts_node_is_null( body ) || !kindIs( ts_node_type( body ), "compound_statement" ) )
    {
        return {};
    }

    // the callee must be a KNOWN test macro
    const TSNode call = ts_node_named_child( exprStmtNode, 0 );
    if( ts_node_is_null( call ) || !kindIs( ts_node_type( call ), "call_expression" ) )
    {
        return {};
    }
    const std::string_view callee = nodeTextOf( fieldChild( call, NodeField::Function ), src );
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

    // the FIRST string literal among the arguments is the title — O(children): `TEST_CASE( /*…*/ "t" )`
    // measured 28x at 16 000 (childwalkscalecheck B25); the cursor above is free again, its walk is done
    const TSNode args  = fieldChild( call, NodeField::Arguments );
    TSNode       title = {};
    if( !ts_node_is_null( args ) )
    {
        forEachNamedChild( args, cursor.cur, [ & ]( TSNode arg )
        {
            if( kindIs( ts_node_type( arg ), "string_literal" ) && ts_node_end_byte( arg ) > ts_node_start_byte( arg ) + 2 )   // "" is not a name
            {
                title = arg;
                return false;
            }
            return true;
        } );
    }
    return ts_node_is_null( title ) ? TestMacroBlockParts {} : TestMacroBlockParts { true, body, title };
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
        if( kindIs( ts_node_type( walk ), "init_declarator" ) )
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
    // O(children): a declaration with no `static` scans its whole child list, comments included — `int /*…*/ m;`
    // measured 16x its control at 16 000 (test/childwalkscalecheck.sh, arm B27)
    std::string_view hit;
    ChildCursor      cursor( node );
    forEachChild( node, cursor.cur, [ & ]( TSNode child )
    {
        const bool isNamed = ts_node_is_named( child );
        if( ( isNamed && std::strcmp( ts_node_type( child ), namedChildType ) != 0 ) || ( !isNamed && !acceptAnonymousToken ) )
        {
            return true;
        }
        const std::uint32_t beginByte = ts_node_start_byte( child );
        const std::uint32_t endByte   = ts_node_end_byte( child );
        if( endByte > src.size() || beginByte >= endByte )
        {
            return true;
        }
        const std::string_view text = src.substr( beginByte, endByte - beginByte );
        for( const std::string_view token : tokens )
        {
            if( text == token )
            {
                hit = text;
                return false;
            }
        }
        return true;
    } );
    return hit;
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
//   Python: the `self.x = …` form (@name's parent is an `attribute`) keeps iff the receiver is the bare
//           identifier `self` AND the assignment
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
    if( !kindIs( ts_node_type( parent ), "attribute" ) )
    {
        return false;
    }
    const TSNode object = fieldChild( parent, NodeField::Object );
    if( ts_node_is_null( object ) || !kindIs( ts_node_type( object ), "identifier" ) || nodeTextOf( object, src ) != "self" )
    {
        return false;   // `obj.x = …` / `cls.x = …` — not an instance attribute of the enclosing class
    }
    bool sawFunction = false;
    for( TSNode up = ts_node_parent( roleNode ); !ts_node_is_null( up ); up = ts_node_parent( up ) )
    {
        const char* ut = ts_node_type( up );
        if( kindIs( ut, "function_definition" ) )
        {
            sawFunction = true;
        }
        else if( kindIs( ut, "class_definition" ) )
        {
            return sawFunction;   // a method of this class (or a closure inside one) → keep; a class-body `self.x` → drop
        }
    }
    return false;       // no enclosing class — `self` is just a name here
}

// INTERNAL LINKAGE of a C/C++ definition (model.h Symbol::internalLinkage; gate test/decltodefcheck.sh arm B2).
// `defNode` is the node that OWNS the definition — the function_definition a function_declarator climbed to
// (ingest_sidecap.h), the declaration for a namespace-scope variable — so its direct children carry the storage
// class and its ancestors are the enclosing scopes. Two shapes, either one suffices:
//   1. an anonymous `namespace { … }` anywhere above it — the `name` field is null (enclosingScopeOf reads the
//      same field and answers "no usable scope" for it). A NAMED class or namespace nested inside one is still
//      internal, so the walk does not stop at the nearest scope owner the way enclosingScopeOf does;
//   2. a `static` storage_class_specifier among defNode's direct children — the same scanner fieldCaptureKept
//      uses for a class-static FIELD — unless the parent is a field_declaration_list: a class-scope `static`
//      member has EXTERNAL linkage and must not be marked (a bodied in-class static method is the case).
// Not covered, all on the "not marked" side, which keeps today's behaviour: an unnamed-struct member, a `static`
// inside a linkage_specification (`extern "C" { static … }` is still internal, but the specifier sits on the
// declaration, which this does see), and an `inline` variable/function in a header (external, correctly).
inline bool cppInternalLinkage( TSNode defNode, std::string_view src ) noexcept
{
    if( ts_node_is_null( defNode ) )
    {
        return false;
    }
    const TSNode parent      = ts_node_parent( defNode );
    const bool   classMember = !ts_node_is_null( parent ) && kindIs( ts_node_type( parent ), "field_declaration_list" );
    if( !classMember && !childTokenAmong( defNode, src, "storage_class_specifier", /*acceptAnonymousToken=*/false, { "static" } ).empty() )
    {
        return true;   // shape 2
    }
    for( TSNode p = parent; !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( kindIs( ts_node_type( p ), "namespace_definition" ) && ts_node_is_null( fieldChild( p, NodeField::Name ) ) )
        {
            return true;   // shape 1
        }
    }
    return false;
}

// The RawDef::internalLinkage value for a def of `lang`: cppInternalLinkage for C and C++, 0 (the SAFE state) for
// every other grammar. The language test lives here so the capture loop in ingest_sidecap.h gains a call, not
// decision points.
inline std::uint8_t internalLinkageBit( Lang lang, TSNode defNode, std::string_view src ) noexcept
{
    if( lang != Lang::Cpp && lang != Lang::C )
    {
        return 0;
    }
    return cppInternalLinkage( defNode, src ) ? std::uint8_t( 1 ) : std::uint8_t( 0 );
}

// One parameter of a block-scope function declarator that an ARGUMENT expression also produces: a bare, qualified or
// template-id type name with no declarator (`Rem`, `Env::Default`), read as a function type (`nextSeed()`) or an array
// (`seeds[ 0 ]`), and nothing else on the node. A primitive type, a cv-qualifier, a named declarator (`Foo other`,
// `Foo* p`, `Foo& r`), an abstract `*` / `&` and an attribute are written only by a prototype.
inline bool cppArgumentShapedParameter( TSNode parameter ) noexcept
{
    const TSNode type       = fieldChild( parameter, NodeField::Type );
    const TSNode declarator = fieldChild( parameter, NodeField::Declarator );
    if( ts_node_is_null( type ) )
    {
        return false;
    }
    const char* typeKind = ts_node_type( type );
    if( !kindIs( typeKind, "type_identifier" ) && !kindIs( typeKind, "qualified_identifier" ) && !kindIs( typeKind, "template_type" ) )
    {
        return false;
    }
    if( !ts_node_is_null( declarator ) && !kindIs( ts_node_type( declarator ), "abstract_function_declarator" )
        && !kindIs( ts_node_type( declarator ), "abstract_array_declarator" ) )
    {
        return false;
    }
    bool        onlyTypeAndDeclarator = true;
    ChildCursor cursor( parameter );
    forEachChild( parameter, cursor.cur, [ & ]( TSNode child )
    {
        if( ts_node_eq( child, type ) || ( !ts_node_is_null( declarator ) && ts_node_eq( child, declarator ) ) || kindIs( ts_node_type( child ), "comment" ) )
        {
            return true;
        }
        onlyTypeAndDeclarator = false;
        return false;
    } );
    return onlyTypeAndDeclarator;
}

// cppBlockScopeDirectInit's declaration question: `extern`, `inline`, `virtual` or `explicit` on the declaration, or a `void`
// return not behind `*` / `&` (`wrapped`) — each written only by a prototype.
inline bool cppDeclarationPrototypeOnly( TSNode decl, bool wrapped, std::string_view src ) noexcept
{
    const TSNode returnType = fieldChild( decl, NodeField::Type );
    if( !wrapped && !ts_node_is_null( returnType ) && kindIs( ts_node_type( returnType ), "primitive_type" ) && nodeTextOf( returnType, src ) == "void" )
    {
        return true;
    }
    bool        prototypeOnly = false;
    ChildCursor cursor( decl );
    forEachChild( decl, cursor.cur, [ & ]( TSNode child )
    {
        const char* kind = ts_node_type( child );
        prototypeOnly    = kindIs( kind, "explicit_function_specifier" )
                        || ( !ts_node_is_named( child ) && kindIs( kind, "virtual" ) )
                        || ( kindIs( kind, "storage_class_specifier" ) && ( nodeTextOf( child, src ) == "extern" || nodeTextOf( child, src ) == "inline" ) );
        return !prototypeOnly;
    } );
    return prototypeOnly;
}

// cppBlockScopeDirectInit's declarator question: nothing but a name and a parameter list (no `const`, `override`, `noexcept`,
// ref-qualifier or trailing return type after it), and that list holds at least one parameter, every one argument-shaped,
// with no `...`.
inline bool cppArgumentListDeclarator( TSNode fnDeclarator ) noexcept
{
    const TSNode name       = fieldChild( fnDeclarator, NodeField::Declarator );
    const TSNode parameters = fieldChild( fnDeclarator, NodeField::Parameters );
    if( ts_node_is_null( name ) || ts_node_is_null( parameters ) )
    {
        return false;
    }
    bool        argumentShaped = true;
    ChildCursor fnCursor( fnDeclarator );
    forEachNamedChild( fnDeclarator, fnCursor.cur, [ & ]( TSNode child )
    {
        argumentShaped = ts_node_eq( child, name ) || ts_node_eq( child, parameters ) || kindIs( ts_node_type( child ), "comment" );
        return argumentShaped;
    } );
    if( !argumentShaped )
    {
        return false;
    }
    std::uint32_t argumentCount = 0;
    ChildCursor   parameterCursor( parameters );
    forEachChild( parameters, parameterCursor.cur, [ & ]( TSNode child )
    {
        const char* kind       = ts_node_type( child );
        const bool  isArgument = ts_node_is_named( child ) && kindIs( kind, "parameter_declaration" );
        argumentCount += isArgument ? 1u : 0u;
        argumentShaped = isArgument ? cppArgumentShapedParameter( child )
                                    : ( ts_node_is_named( child ) ? kindIs( kind, "comment" ) : ( kindIs( kind, "(" ) || kindIs( kind, ")" ) || kindIs( kind, "," ) ) );
        return argumentShaped;
    } );
    return argumentShaped && argumentCount > 0;
}

// Most-vexing-parse round (test/narrowcheck.sh arms 52-60) — the C++ twin of F5's Swift local binding. A block-scope
// DIRECT-INITIALIZED local whose every argument is a plain name — `IRBuilder<> Builder(Rem);`, `std::lock_guard<std::mutex>
// Lock(Mtx);` — is, to a grammar that cannot tell a name from a type, a local FUNCTION declaration: a function_declarator
// with one parameter_declaration per argument. queries/cpp/tags.scm minted a function symbol for the variable, and since a
// symbol's span is the innermost cover of its own declaration, the local's Rule 2 type binding was attributed to that phantom
// instead of to the function the local lives in: Rule 2 looked up `<enclosing fn>#Builder`, found nothing, and every
// `Builder.CreateX()` fell to the name ladder. The phantom also answered bare-name lookups for `lock`, `end`, `iter`.
//
// The language's own rule — a declaration that CAN be a function declaration IS one — turns on whether `Rem` names a type,
// which a tags pass cannot know. So the decision is syntactic and one-sided: the declarator reads as a VARIABLE only when it
// is block-scope (a function or lambda body is the nearest scope owner) and nothing in it is written only by a prototype.
// Any of these keeps the function symbol, exactly as before:
//   * `extern`, `inline`, `virtual` or `explicit` on the declaration, or a `void` return not behind `*` / `&`;
//   * anything after the parameter list — `const`, `override`, `noexcept`, a ref-qualifier, a trailing return type. A class
//     body the grammar misreads as a function body (an export macro before the class name) lands here with its members;
//   * an empty parameter list — `Foo x();` declares a function by the language's own rule;
//   * a parameter an argument cannot produce (cppArgumentShapedParameter), a default value, or `...`.
// Measured 2026-09-17, --pin-census S rows before and after: 12,543 function symbols gone on llvm-project 4d5358b1d and 2,443
// on rocksdb 0e2801ac3, none added — every sampled one a direct-initialized local (or a macro statement, which declares no
// function either). FLOOR, pinned by arm 60: `Widget w( a * b )` parses as the pointer parameter `a* b`, which a prototype
// writes too, so it stays a function symbol.
inline bool cppBlockScopeDirectInit( TSNode fnDeclarator, std::string_view src ) noexcept
{
    // the declarator of a DECLARATION, through the `*` / `&` it may sit under. A definition's, a member's or a parameter's
    // function_declarator stops at the first parent — almost every capture this pattern makes.
    TSNode decl    = ts_node_parent( fnDeclarator );
    bool   wrapped = false;
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ) && ( kindIs( ts_node_type( decl ), "pointer_declarator" ) || kindIs( ts_node_type( decl ), "reference_declarator" ) ); ++guard )
    {
        wrapped = true;
        decl    = ts_node_parent( decl );
    }
    if( ts_node_is_null( decl ) || !kindIs( ts_node_type( decl ), "declaration" ) )
    {
        return false;
    }
    // block scope: a function or lambda body owns the declaration before any class, namespace or file scope does
    return !cppDeclarationPrototypeOnly( decl, wrapped, src ) && cppArgumentListDeclarator( fnDeclarator )
        && nearestScopeOwnerIs( decl, { "function_definition", "lambda_expression" }, { "field_declaration_list", "declaration_list", "translation_unit" } );
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
    if( kindIs( ts_node_type( roleNode ), "field_declaration" ) )
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
        if( kindIs( pt, "block_mapping" ) || kindIs( pt, "flow_mapping" ) )
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
    if( defCapSv == "definition.function" )
    {
        return lang == Lang::Cpp && cppBlockScopeDirectInit( roleNode, src );   // most-vexing-parse round: a local variable, not a function
    }
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
            && kindIs( ts_node_type( defineNode ), "preproc_function_def" )
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
    const TSNode obj = fieldChild( member, NodeField::Object );
    if( ts_node_is_null( obj ) )
    {
        return false;
    }
    const char* objType = ts_node_type( obj );
    if( kindIs( objType, "identifier" ) )
    {
        return nodeTextOf( obj, src ) == "exports";
    }
    if( kindIs( objType, "member_expression" ) )
    {
        const TSNode oo = fieldChild( obj, NodeField::Object );
        return kindIs( ts_node_type( oo ), "identifier" )
            && nodeTextOf( oo, src ) == "module"
            && nodeTextOf( fieldChild( obj, NodeField::Property ), src ) == "exports";
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
    const TSNode obj = fieldChild( member, NodeField::Object );
    if( ts_node_is_null( obj ) || !kindIs( ts_node_type( obj ), "member_expression" ) )
    {
        return false;
    }
    return nodeTextOf( fieldChild( obj, NodeField::Property ), src ) == "prototype";
}

// Constructor identifier of `Foo.prototype.NAME` (the object of the inner `.prototype` member).
// `String.prototype.shout` → "String"; `net.Socket.prototype.x` → "Socket". Empty if the shape
// is not a prototype member. Used as RawDef::scope so a Lit* call can bind only an extension of
// that built-in (issue #163).
inline std::string_view prototypeCtorName( TSNode nameNode, std::string_view src ) noexcept
{
    if( !isPrototypeMemberTarget( nameNode, src ) )
    {
        return {};
    }
    const TSNode member     = ts_node_parent( nameNode );
    const TSNode protoMember = fieldChild( member, NodeField::Object );
    const TSNode ctor       = fieldChild( protoMember, NodeField::Object );
    if( ts_node_is_null( ctor ) )
    {
        return {};
    }
    const char* ct = ts_node_type( ctor );
    if( kindIs( ct, "identifier" ) )
    {
        return nodeTextOf( ctor, src );
    }
    if( kindIs( ct, "member_expression" ) )
    {
        return nodeTextOf( fieldChild( ctor, NodeField::Property ), src );
    }
    return {};
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
    if( ts_node_is_null( cls ) || !kindIs( ts_node_type( cls ), "class_definition" ) )
    {
        return false;
    }
    const TSNode bases = fieldChild( cls, NodeField::Superclasses );
    if( ts_node_is_null( bases ) )
    {
        return false;
    }
    // O(children): the superclasses argument_list owns every comment between its names — `class C( # …
    // Enum ):` measured 54x its control at 16 000 (test/childwalkscalecheck.sh, arm B28)
    bool        isEnum = false;
    ChildCursor cursor( bases );
    forEachNamedChild( bases, cursor.cur, [ & ]( TSNode base )
    {
        if( kindIs( ts_node_type( base ), "attribute" ) )                      // models.TextChoices → TextChoices
        {
            base = fieldChild( base, NodeField::Attribute );
            if( ts_node_is_null( base ) )
            {
                return true;
            }
        }
        if( !kindIs( ts_node_type( base ), "identifier" ) )
        {
            return true;
        }
        const std::string_view baseName = nodeTextOf( base, src );
        isEnum =    baseName == "Enum" || baseName == "IntEnum" || baseName == "StrEnum"
                 || baseName == "Flag" || baseName == "IntFlag" || baseName == "ReprEnum"
                 || baseName == "Choices" || baseName == "TextChoices" || baseName == "IntegerChoices";
        return !isEnum;
    } );
    return isEnum;
}
}   // namespace — ingest_names.h section of ingest.cpp

}   // namespace rw
