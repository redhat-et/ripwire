#pragma once

// verify.h — G4 VERIFY-A-CLAIM: the parser and shared vocabulary for `--verify="CLAIM"`.
//
// The month-scale usage mine's single biggest verb-less intent is VERIFICATION: "does X really call Y?",
// "is Z ever used?", "does this file handle A?" — answered today by a manual grep-chain plus reading,
// because the DATA all exists (--path, --uses, --grep, --impact) but no verb takes the CLAIM and returns
// a VERDICT. --verify is that verb: one structured claim in, one three-valued verdict out, with the
// evidence rows inline and the honesty vocabulary (complete= / counts_floor= / limit=) deciding which
// verdicts the index can actually support.
//
// THE CLAIM LANGUAGE IS CLOSED — a fixed shape set, like --graph-query's operator set, and for the same
// reason: a bounded language can refuse loudly and completely, an open one can only guess. The shapes:
//
//   calls( A , B )             does A transitively CALL B (directed, over the indexed call graph)
//   uses( SYM )                is SYM referenced anywhere (call/read/write/import/extends sites)
//   unused( SYM )              is SYM referenced nowhere
//   contains( FILE , "LIT" )   do FILE's indexed bytes contain the literal LIT
//   defines( FILE , SYM )      does FILE define SYM
//   reaches( SYM , "FILE" )    does code in a file matching FILE transitively call SYM
//   reaches( SYM , LAYER )     same, LAYER from the built-in taxonomy (unquoted; quoted means FILE)
//
// SYM takes the shared selector grammar (bare name, file:name, canonical id). FILE is a path substring
// (filePathContains — the same rule the file: qualifier uses). A quoted second argument is scanned to its
// closing quote FIRST, so commas inside a literal never split the argument list.
//
// THE VERDICT GRAMMAR (the heart — src/main.cpp's runVerify emits it, test/verifycheck.sh pins it):
//   confirmed        — a witness exists and is printed (a path, use-sites, hits, a definition row).
//   refuted          — only where the evidence is COMPLETE: a literal-scan absence (contains, and the
//                      defines literal check) carries complete= per the T1 claim rules; an absence-claim
//                      (unused) is refuted by printed witness sites. A graph/reference ZERO never refutes.
//   not-established  — the absence is real within the model but the model is a FLOOR; limit= names the
//                      limiting factor. It never means "false".
//
// Parsing is deliberately dumb and total: no recursion, no nesting, no escapes inside quotes — a claim
// is one shape word, one paren pair, one or two arguments. Anything else refuses with the whole
// vocabulary in the message (the --graph-query refusal posture).

#include <cctype>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <string>
#include <string_view>

namespace rw
{
namespace verify
{

// ── the closed shape set ─────────────────────────────────────────────────────────────────────────────
enum class ClaimShape : std::uint8_t { Calls, Uses, Unused, Contains, Defines, Reaches };

// ── the vocabulary, stated ONCE — the refusal message and the docs both speak it ─────────────────────
inline constexpr const char* kShapeVocabulary =
    "calls(A, B) does A transitively call B · uses(SYM) is SYM referenced anywhere · "
    "unused(SYM) is SYM referenced nowhere · contains(FILE, \"LITERAL\") do FILE's bytes contain the literal · "
    "defines(FILE, SYM) does FILE define SYM · reaches(SYM, \"FILE\") / reaches(SYM, LAYER) does code there "
    "transitively call SYM (LAYER unquoted, one of game|infra|render|math|audio|ai|test; quoted means FILE)";

// One parsed claim. `ok=false` ⇒ `err` carries the complete, user-ready refusal (the CLI prints it
// verbatim to stderr and exits 1 — a malformed claim is a user error, never a measurement).
struct Claim
{
    ClaimShape       shape      = ClaimShape::Calls;
    std::string_view arg1;                    // trimmed; never quoted (SYM or FILE)
    std::string_view arg2;                    // trimmed; empty on 1-argument shapes
    bool             arg2Quoted = false;      // true ⇔ arg2 was a "..." literal (contains' LIT, reaches' FILE)
    bool             ok         = false;
    std::string      err;
};

namespace claim_detail
{
    inline std::string_view trimWs( std::string_view s ) noexcept
    {
        while( !s.empty() && std::isspace( static_cast<unsigned char>( s.front() ) ) ) { s.remove_prefix( 1 ); }
        while( !s.empty() && std::isspace( static_cast<unsigned char>( s.back() ) ) )  { s.remove_suffix( 1 ); }
        return s;
    }

    inline Claim refuse( std::string_view got, const char* why )
    {
        Claim c;
        c.ok  = false;
        c.err = std::string( "ripwire: --verify claim not recognized: '" ) + std::string( got ) + "' — " + why
              + ". The claim language is CLOSED; the shapes are: " + kShapeVocabulary;
        return c;
    }
} // namespace claim_detail

// Parse one claim. Whitespace-insensitive around every token. Returns ok=false with the full refusal
// text on ANY deviation — unknown shape word, wrong arity, unbalanced parens/quotes, trailing bytes.
inline Claim parseClaim( std::string_view src )
{
    using claim_detail::refuse;
    using claim_detail::trimWs;

    const std::string_view whole = trimWs( src );

    // shape word up to '('
    const std::size_t open = whole.find( '(' );
    if( open == std::string_view::npos )
    {
        return refuse( whole, "no '(' — a claim is SHAPE(ARGS)" );
    }
    const std::string_view word = trimWs( whole.substr( 0, open ) );

    Claim c;
    int   arity = 2;
    if(      word == "calls"    ) { c.shape = ClaimShape::Calls;    arity = 2; }
    else if( word == "uses"     ) { c.shape = ClaimShape::Uses;     arity = 1; }
    else if( word == "unused"   ) { c.shape = ClaimShape::Unused;   arity = 1; }
    else if( word == "contains" ) { c.shape = ClaimShape::Contains; arity = 2; }
    else if( word == "defines"  ) { c.shape = ClaimShape::Defines;  arity = 2; }
    else if( word == "reaches"  ) { c.shape = ClaimShape::Reaches;  arity = 2; }
    else
    {
        return refuse( whole, "unknown shape word" );
    }

    if( whole.back() != ')' )
    {
        return refuse( whole, "no closing ')'" );
    }
    std::string_view args = whole.substr( open + 1, whole.size() - open - 2 );   // between the parens

    // argument 1 — a bare token up to the first ',' (or the whole args on arity 1)
    if( arity == 1 )
    {
        c.arg1 = trimWs( args );
        if( c.arg1.empty() )
        {
            return refuse( whole, "the shape takes one argument, got none" );
        }
        if( c.arg1.find( ',' ) != std::string_view::npos )
        {
            return refuse( whole, "the shape takes one argument, got several" );
        }
        c.ok = true;
        return c;
    }
    const std::size_t comma = args.find( ',' );
    if( comma == std::string_view::npos )
    {
        return refuse( whole, "the shape takes two arguments, got one" );
    }
    c.arg1 = trimWs( args.substr( 0, comma ) );
    if( c.arg1.empty() )
    {
        return refuse( whole, "the first argument is empty" );
    }

    // argument 2 — QUOTE-FIRST: a leading '"' scans to the closing '"' verbatim (no escapes), so a comma
    // inside a contains() literal never splits; only then may nothing but whitespace remain.
    std::string_view rest = trimWs( args.substr( comma + 1 ) );
    if( !rest.empty() && rest.front() == '"' )
    {
        const std::size_t close = rest.find( '"', 1 );
        if( close == std::string_view::npos )
        {
            return refuse( whole, "unterminated '\"' in the second argument" );
        }
        c.arg2       = rest.substr( 1, close - 1 );
        c.arg2Quoted = true;
        if( !trimWs( rest.substr( close + 1 ) ).empty() )
        {
            return refuse( whole, "trailing bytes after the quoted argument" );
        }
    }
    else
    {
        if( rest.find( ',' ) != std::string_view::npos )
        {
            return refuse( whole, "the shape takes two arguments, got more" );
        }
        c.arg2 = rest;
    }
    if( c.arg2.empty() && !c.arg2Quoted )
    {
        return refuse( whole, "the second argument is empty" );
    }
    // an EMPTY quoted literal is a degenerate contains() ("" occurs everywhere) — refuse it as a user
    // error rather than confirming vacuously.
    if( c.arg2Quoted && c.arg2.empty() )
    {
        return refuse( whole, "the quoted literal is empty — an empty string occurs everywhere, so the claim measures nothing" );
    }
    c.ok = true;
    return c;
}

// the tag the emitter prints for a shape (shape= is what a consumer switches on, so the spelling is
// pinned here where the parser lives). A declarative table, no lookup helper: the parser is the only
// producer of ClaimShape values and every one it produces is in range, so the emitter indexes the table
// directly (with a VERIFY at the use-site) — the enum order IS the tag order, and the static_assert pins
// the count so a new shape cannot silently miss a tag.
inline constexpr const char* kShapeTags[] = { "calls", "uses", "unused", "contains", "defines", "reaches" };
static_assert( std::size_t( ClaimShape::Reaches ) + 1 == std::size( kShapeTags ), "ClaimShape grew — extend kShapeTags" );

// ── the limit= vocabulary — the not-established verdict's REASON, closed like the shapes ─────────────
inline constexpr const char* kLimitCallGraphFloor   = "call-graph-floor";     // name-based edges: dynamic dispatch/fn-ptr/macros may be missing
inline constexpr const char* kLimitReferenceFloor   = "reference-floor";      // identifier-based reference index: string-keyed/dynamic references invisible
inline constexpr const char* kLimitCollectionCeiling = "collection-ceiling";  // the literal scan hit its collection budget — hits are a floor
inline constexpr const char* kLimitScanDegraded     = "scan-degraded";        // a file was unreadable or a scan worker degraded
inline constexpr const char* kLimitExtractionFloor  = "extraction-floor";     // the name occurs in the file but no definition was extracted

// ── the legend, stated once — G4-terse, no attribute=value numeric literal (gates grep headers) ──────
inline constexpr const char* kVerifyLegend =
    "<!-- ripwire verify: ONE structured claim in, a three-valued verdict out, evidence inline. "
    "verdict= is confirmed (a witness exists and is printed: a call path, use-sites, hits, a definition row), "
    "refuted (only with COMPLETE evidence: a literal-scan absence carries complete=, an absence-claim is refuted by printed witness sites), "
    "or not-established (the absence is real WITHIN THE MODEL but the model is a floor; limit= names the limiting factor and it NEVER means false). "
    "The limits: call-graph-floor (call edges are name-based — dynamic dispatch, unbound fn-pointers and unindexed macros contribute no edge), "
    "reference-floor (references are identifier-based — a string-keyed or reflective use is invisible), "
    "collection-ceiling (the scan's collection budget was reached, so counts are floors), scan-degraded (a file could not be read), "
    "extraction-floor (the name occurs in the file but no definition was extracted — a construct the parser may not model). "
    "complete= on the root (value 1) means the printed evidence is EXHAUSTIVE over the index for a literal scan and the verdict may be trusted as a "
    "complete-within-the-index answer: files the ingest skipped were never scanned (the skipped verb lists them). "
    "counts_floor= on the root marks every count as a FLOOR, never a total — the two claims are mutually exclusive by construction. "
    "calls/reaches can never refute; unused can never confirm. defines() does not require the symbol to exist anywhere (the claim is about the FILE), "
    "so a refuted defines means the name token never occurs in that file's indexed bytes. "
    "reaches' direction: some symbol defined in the named file or layer transitively CALLS the target. "
    "Evidence rows are a bounded sample when capped (disclosed on the root); every total lives in the attributes. "
    // M12: a uses()/unused() <u> row's in_id= — the same attribute --uses itself defines (kUsesLegendOpen), stated
    // again here because this element's legend is its own leading comment run, not --uses'.
    "A uses()/unused() <u> row's in_id= is the canonical id (root-relative path::scope::name) of the enclosing "
    "symbol, degrading to a bare name when unscoped and absent at file scope. -->";

} // namespace verify
} // namespace rw
