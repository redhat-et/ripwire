#pragma once

// search.h — literal + regex substring search (--grep / --regex), scanned DIRECTLY and IN PARALLEL.
//
// History, and why the index is gone (P3, 2026-07-27): this file used to build a Google-Code-Search /
// Zoekt style file-level trigram index (RESEARCH_codeIntelligence §1) — a serial `fread` of every file
// plus a `vector<uint32_t>` holding one trigram PER BYTE POSITION (4 B per source byte), sorted and
// uniq'd — and then threw the whole thing away after ONE query. Measured on a 2815-file C++ tree:
// 1860 ms wall / 814 MB peak RSS, of which ~1.6 s was single-threaded, against a 0.3 s read-verb budget
// and a 100 ms default map on the same tree. Building the index is strictly MORE work than the one scan
// it was meant to save: an inverted index only pays off when it is amortized over many queries, and a
// one-shot CLI invocation has exactly one.
//
// So: no index. Every file is read + scanned once, on the ingest-sized thread pool (~12-way here), and
// nothing but the surviving hits is retained. The regex prefilter SURVIVES in a cheaper form — the same
// sound Russ-Cox regex→trigram query is evaluated directly against each file's bytes (triQueryMatchesText)
// instead of against posting lists, so `--regex` still skips the std::regex verifier on files that cannot
// possibly match, and `--no-prefilter` still forces the full-scan oracle the soundness gate compares to.
// The real agent-value over raw grep is unchanged and is not the index: it is CODE-AWARENESS — every hit
// carries its enclosing symbol chain, its matched line, and optional context lines.

#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade when regex matching throws mid-scan (never terminate)
#include "docparse.h"      // docparse::detail::readWholeFile — the canonical whole-file byte read (reused, not re-rolled)
#include "filter.h"        // §P11.1: ctx::pathTierOf — the shared source/test/doc ORDERING tier
#include "model.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <iterator>
#include <optional>
#include <regex>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace ctx
{

inline std::uint32_t triAt( const std::string& s, std::size_t i ) noexcept
{
    return ( std::uint32_t( (unsigned char)s[i] )     << 16 )
         | ( std::uint32_t( (unsigned char)s[i + 1] ) <<  8 )
         |   std::uint32_t( (unsigned char)s[i + 2] );
}

// One literal-search hit, already enriched with its enclosing symbol — the shared core behind the
// --grep CLI and the MCP `grep` verb (so they never diverge). `text` is the MATCHED LINE itself (raw,
// unescaped, never containing a newline, capped at kGrepMatchedLineMaxBytes) — without it a --grep hit
// told an agent WHERE the pattern is but never WHAT it matched, so every hit cost a follow-up read
// (P5). `before`/`after` are ripgrep-style context lines (--grep-context/-before/-after, CLI-only):
// each is the raw (unescaped, newline-joined) source text of the N lines immediately surrounding the
// hit line, clamped to the file's bounds, and empty when no context was requested.
struct GrepHit { std::uint32_t fileId; std::uint32_t line; std::string enclosing; std::string text; std::string before; std::string after; };

// ─── Russ Cox regex→trigram prefilter ─────────────────────────────────────────────────────────────
//
// Make --regex SUB-LINEAR by deriving, from the regex itself, a SOUND boolean-of-trigrams query — then
// answer that query against the SAME posting lists --grep uses, and verify (std::regex) ONLY the
// candidate files. The method is Russ Cox's "Regular Expression Matching with a Trigram Index"
// (swtch.com/~rsc/regexp/regexp4.html / Google Code Search): walk the regex AST and compute bottom-up
//   { canEmpty, exact, prefix, suffix, match }
// where `exact` is the (capped) set of strings the subexpression can match exactly (or ⊤ = unknown),
// `prefix`/`suffix` are capped string sets the subexpression's matches must begin/end with, and `match`
// is an AND/OR-of-trigrams boolean QUERY that is a SOUND OVER-APPROXIMATION: any text the subexpression
// matches must satisfy `match`. SOUNDNESS is the whole point — `match` may keep extra files but must
// NEVER exclude a file that genuinely matches. Whenever a subexpression yields no usable trigram
// constraint (`.`, `a|b` over <3-char alts, anchors-only, an unbounded `.*` …) its `match` collapses to
// ALL (the always-true query) → the evaluator returns every file → we fall back to a full scan. The
// std::regex verifier then guarantees the final result equals a full scan exactly.

// A boolean query over trigrams, in a normalized AND/OR tree. ALL = always-true (no constraint, ⇒ scan
// all files); NONE = always-false (a required trigram occurs nowhere ⇒ no file can match). A Trigram leaf
// is "this 24-bit trigram must be present"; And/Or compose children. Kept tiny + value-typed (DOD-ish).
struct TriQuery
{
    enum class Op : std::uint8_t { All, None, And, Or, Trigram };
    Op                    op  = Op::All;
    std::uint32_t         tri = 0;          // valid when op == Trigram (24-bit packed trigram)
    std::vector<TriQuery> kids;             // valid when op == And / Or

    static TriQuery all()                       { return TriQuery{ Op::All,  0, {} }; }
    static TriQuery none()                      { return TriQuery{ Op::None, 0, {} }; }
    static TriQuery trigram( std::uint32_t t )  { return TriQuery{ Op::Trigram, t, {} }; }
};

// AND two queries with the absorbing/identity simplifications (ALL is AND-identity, NONE is AND-zero).
// Flattens nested Ands so the evaluator sees one level. Sound: result is true iff BOTH inputs are true.
inline TriQuery andOf( TriQuery a, TriQuery b )
{
    if( a.op == TriQuery::Op::None || b.op == TriQuery::Op::None ) return TriQuery::none();
    if( a.op == TriQuery::Op::All ) return b;
    if( b.op == TriQuery::Op::All ) return a;
    TriQuery q; q.op = TriQuery::Op::And;
    auto absorb = [ &q ]( TriQuery& x ) { if( x.op == TriQuery::Op::And ) for( auto& k : x.kids ) q.kids.push_back( std::move( k ) ); else q.kids.push_back( std::move( x ) ); };
    absorb( a ); absorb( b );
    return q;
}

// OR two queries with simplifications (ALL is OR-zero/absorbing, NONE is OR-identity). Flattens nested
// Ors. Sound: result is true iff EITHER input is true — so an ALL child makes the whole OR unconstrained.
inline TriQuery orOf( TriQuery a, TriQuery b )
{
    if( a.op == TriQuery::Op::All || b.op == TriQuery::Op::All ) return TriQuery::all();
    if( a.op == TriQuery::Op::None ) return b;
    if( b.op == TriQuery::Op::None ) return a;
    TriQuery q; q.op = TriQuery::Op::Or;
    auto absorb = [ &q ]( TriQuery& x ) { if( x.op == TriQuery::Op::Or ) for( auto& k : x.kids ) q.kids.push_back( std::move( k ) ); else q.kids.push_back( std::move( x ) ); };
    absorb( a ); absorb( b );
    return q;
}

// The AND of "string s contains this trigram" for every trigram of s (Cox's `trigrams(s)`): the soundest
// constraint a known literal contributes. s shorter than 3 bytes carries no trigram ⇒ ALL (no constraint).
inline TriQuery triQueryOfString( const std::string& s )
{
    if( s.size() < 3 ) return TriQuery::all();
    TriQuery q = TriQuery::all();
    for( std::size_t i = 0; i + 3 <= s.size(); ++i ) q = andOf( std::move( q ), TriQuery::trigram( triAt( s, i ) ) );
    return q;
}

// The OR over a set of alternatives of triQueryOfString — the match query for an `exact` string set: text
// must equal one of them, so it must satisfy that one's trigram AND. Any element <3 chars (⇒ ALL) makes
// the whole OR unconstrained (sound: a short alt can match with no trigram evidence). Empty set = NONE.
inline TriQuery triQueryOfStringSet( const std::vector<std::string>& set )
{
    if( set.empty() ) return TriQuery::none();
    TriQuery q = TriQuery::none();
    for( const std::string& s : set ) q = orOf( std::move( q ), triQueryOfString( s ) );
    return q;
}

// Cox's RegexInfo lattice element, computed bottom-up. `exactKnown` distinguishes a KNOWN finite exact set
// from ⊤ ("could be anything" — e.g. after a `.` or a `+`). prefix/suffix are always finite capped sets of
// the strings matches must begin / end with; `match` is the sound trigram query. canEmpty = can match "".
struct RegexInfo
{
    bool                     canEmpty = false;
    bool                     exactKnown = false;       // true ⇒ `exact` is the complete set of matchable strings
    std::vector<std::string> exact;                    // valid iff exactKnown
    std::vector<std::string> prefix;                   // strings every match must START with (capped)
    std::vector<std::string> suffix;                   // strings every match must END with (capped)
    TriQuery                 match = TriQuery::all();   // sound over-approx trigram query
};

// Caps that bound the analysis cost + keep the boolean query small. Crossing a cap is ALWAYS handled by
// DEGRADING toward ALL / ⊤ (sound: fewer constraints ⇒ keep more candidates), never by dropping a match.
inline constexpr std::size_t kMaxExactSet = 8;     // beyond this many exact strings, give up exactness (⊤)
inline constexpr std::size_t kMaxExactLen = 24;    // beyond this exact-string length, give up exactness (⊤)
inline constexpr std::size_t kMaxAffixSet = 8;     // cap on prefix/suffix set sizes

// sorted-unique a small string set (determinism + dedup) and report whether it stayed within `cap`.
inline bool normSet( std::vector<std::string>& v, std::size_t cap )
{
    std::sort( v.begin(), v.end() );
    v.erase( std::unique( v.begin(), v.end() ), v.end() );
    return v.size() <= cap;
}

// Fold an `exact` set into the `match` query and mark it unknown (⊤). Used whenever a set grows past a cap
// or a node (., +, repetition) makes the exact set infinite: we keep the trigram evidence we already have
// (sound) but stop tracking exact strings. prefix/suffix are seeded from the (now-frozen) exact set first.
inline void dropExact( RegexInfo& r )
{
    if( !r.exactKnown ) return;
    r.match  = andOf( std::move( r.match ), triQueryOfStringSet( r.exact ) );
    r.prefix = r.exact;  normSet( r.prefix, kMaxAffixSet );  if( r.prefix.size() > kMaxAffixSet ) r.prefix.clear();
    r.suffix = r.exact;  normSet( r.suffix, kMaxAffixSet );  if( r.suffix.size() > kMaxAffixSet ) r.suffix.clear();
    r.exact.clear();
    r.exactKnown = false;
}

// ── RegexInfo constructors for the AST leaf/operator nodes (Cox §"Computing the trigram query") ──

// EMPTY (ε): matches only "" — exact = {""}, canEmpty, no trigram constraint.
inline RegexInfo riEmpty()
{
    RegexInfo r; r.canEmpty = true; r.exactKnown = true; r.exact = { std::string() }; return r;
}

// A literal exact string (a run of ordinary chars). exact = {s}; the rest derive in the concat/finish step.
inline RegexInfo riLiteral( const std::string& s )
{
    if( s.empty() ) return riEmpty();
    RegexInfo r; r.exactKnown = true; r.exact = { s }; r.canEmpty = false; return r;
}

// ANY single char (`.`) or a char class `[...]` we don't enumerate: matches one unknown byte ⇒ exact is ⊤,
// no prefix/suffix/trigram constraint. This is the soundness escape hatch — it contributes ALL.
inline RegexInfo riAnyChar()
{
    RegexInfo r; r.canEmpty = false; r.exactKnown = false; r.match = TriQuery::all(); return r;
}

// A char class enumerated to a small set of single-char alternatives (e.g. `[abc]`). Treated as an exact
// set of 1-char strings — composes through concatenation to build cross-product trigrams at the seams.
inline RegexInfo riCharSet( std::vector<std::string> oneChar )
{
    if( !normSet( oneChar, kMaxExactSet ) || oneChar.size() > kMaxExactSet ) return riAnyChar();
    RegexInfo r; r.canEmpty = false; r.exactKnown = true; r.exact = std::move( oneChar ); return r;
}

// ANCHOR (^ or $) / other zero-width assertion: matches "" with no trigram evidence (Cox treats anchors as
// empty for indexing). Returns ε so concatenation neither adds nor removes constraints (anchors-only ⇒ ALL).
inline RegexInfo riAnchor() { return riEmpty(); }

// Does this subexpression match ONLY the empty string (a pure ε / anchor)? This is the precise condition
// under which an adjacency seam may cross it. An empty-able-but-not-only-empty node (`.*`, `a?`, `x*`) can
// consume bytes, so a left literal is NOT adjacent to what follows it through such a node — propagating the
// left's suffix as a seam across it would be UNSOUND (it would require `LeftRight` trigrams that need not
// appear). matchesOnlyEmpty distinguishes "ε" (seam crosses) from "can be empty but might not" (seam stops).
inline bool matchesOnlyEmpty( const RegexInfo& r )
{
    return r.exactKnown && r.exact.size() == 1 && r.exact.front().empty();
}

// the cross product of two small string sets (for concat of two exact sets), capped → degrade signalled by
// returning false. Building exact = { x+y : x∈a, y∈b } is how literal seams across an alternation surface
// (e.g. `(ab|cd)(ef|gh)` → abef, abgh, cdef, cdgh, whose trigrams the AND can then require).
inline bool crossProduct( const std::vector<std::string>& a, const std::vector<std::string>& b, std::vector<std::string>& out )
{
    if( a.size() * b.size() > kMaxExactSet ) return false;
    out.clear();
    for( const std::string& x : a )
        for( const std::string& y : b )
        {
            if( x.size() + y.size() > kMaxExactLen ) return false;
            out.push_back( x + y );
        }
    return normSet( out, kMaxExactSet ) && out.size() <= kMaxExactSet;
}

// the cross product for affixes: { x+y } but only keeping the trailing (suffix) / leading (prefix) bytes
// that could form a NEW seam trigram. We keep it simple+sound by bounding length to kMaxExactLen and
// degrading (clear ⇒ no constraint) on overflow.
inline std::vector<std::string> affixCross( const std::vector<std::string>& a, const std::vector<std::string>& b )
{
    std::vector<std::string> out;
    if( a.empty() || b.empty() || a.size() * b.size() > kMaxAffixSet ) return out;   // empty ⇒ caller keeps no constraint
    for( const std::string& x : a )
        for( const std::string& y : b )
        {
            std::string s = x + y;
            if( s.size() > kMaxExactLen ) return {};
            out.push_back( std::move( s ) );
        }
    if( !normSet( out, kMaxAffixSet ) || out.size() > kMaxAffixSet ) return {};
    return out;
}

// CONCATENATION r = a · b (Cox's hardest case). The seam between a's matches and b's matches creates
// trigrams neither side sees alone — so when both sides have known exact sets we take their cross product
// (exactness preserved); otherwise we AND the two match queries AND the seam trigrams formed from a.suffix ×
// b.prefix. Every branch is a sound over-approximation.
inline RegexInfo riConcat( RegexInfo a, RegexInfo b )
{
    RegexInfo r;
    r.canEmpty = a.canEmpty && b.canEmpty;

    // both exact + small ⇒ exact cross product (keeps full precision; trigrams derived later at finish)
    if( a.exactKnown && b.exactKnown )
    {
        std::vector<std::string> prod;
        if( crossProduct( a.exact, b.exact, prod ) )
        {
            r.exactKnown = true;
            r.exact      = std::move( prod );
            return r;
        }
        // overflow → fall through to the inexact path, but first push each side's exact into its match
        dropExact( a );
        dropExact( b );
    }
    else
    {
        dropExact( a );
        dropExact( b );
    }

    // inexact concat: AND both match queries, AND the seam trigrams (a.suffix × b.prefix), and propagate
    // outer prefix/suffix (a's prefix becomes r's prefix unless a can be empty, in which case b's prefix
    // also reaches the front; symmetrically for suffix).
    r.exactKnown = false;
    r.match = andOf( std::move( a.match ), std::move( b.match ) );

    // seam trigrams: every concatenation of a-suffix-tail and b-prefix-head must appear in any match
    {
        const std::vector<std::string> seam = affixCross( a.suffix, b.prefix );
        if( !seam.empty() )
            r.match = andOf( std::move( r.match ), triQueryOfStringSet( seam ) );
    }

    // outer prefix: the front of x·y is x's front; y's front also reaches the front ONLY when x is pure ε
    // (matchesOnlyEmpty) — an inexact empty-able x (`.*`, `a?`) can consume bytes, so its presence does not
    // let y's prefix become the seam prefix (that would be unsound for `.*Bar` etc.).
    if( matchesOnlyEmpty( a ) )
    {
        std::vector<std::string> pre = a.prefix;
        for( const std::string& s : b.prefix ) pre.push_back( s );
        if( normSet( pre, kMaxAffixSet ) && pre.size() <= kMaxAffixSet ) r.prefix = std::move( pre );
        else r.prefix.clear();
    }
    else r.prefix = a.prefix;

    // outer suffix: symmetric — y's suffix is the suffix of x·y; x's suffix also reaches the end ONLY when y
    // is pure ε. Otherwise (e.g. y = `.*`), x's suffix must NOT propagate (the bug `Foo.*Bar` ⇒ false
    // `FooBar` seam was exactly this — `.*` between Foo and Bar breaks adjacency, dropping real matches).
    if( matchesOnlyEmpty( b ) )
    {
        std::vector<std::string> suf = b.suffix;
        for( const std::string& s : a.suffix ) suf.push_back( s );
        if( normSet( suf, kMaxAffixSet ) && suf.size() <= kMaxAffixSet ) r.suffix = std::move( suf );
        else r.suffix.clear();
    }
    else r.suffix = b.suffix;

    return r;
}

// ALTERNATION r = a | b: a match is a match of EITHER side ⇒ union exact/prefix/suffix sets and OR the
// match queries. If either side is inexact (⊤), the union exactness is lost; prefix/suffix unions still
// hold (every match still begins with one of the combined prefixes). OR-ing match keeps soundness: text
// matching r matches a or b, so it satisfies a.match or b.match.
inline RegexInfo riAlternate( RegexInfo a, RegexInfo b )
{
    RegexInfo r;
    r.canEmpty = a.canEmpty || b.canEmpty;

    if( a.exactKnown && b.exactKnown )
    {
        std::vector<std::string> ex = a.exact;
        for( const std::string& s : b.exact ) ex.push_back( s );
        if( normSet( ex, kMaxExactSet ) && ex.size() <= kMaxExactSet )
        {
            r.exactKnown = true;
            r.exact      = std::move( ex );
            return r;
        }
        dropExact( a );
        dropExact( b );
    }
    else
    {
        dropExact( a );
        dropExact( b );
    }

    r.exactKnown = false;
    r.match = orOf( std::move( a.match ), std::move( b.match ) );

    // prefix union (drop to "no constraint" on overflow — sound)
    {
        std::vector<std::string> pre = a.prefix;
        for( const std::string& s : b.prefix ) pre.push_back( s );
        if( a.prefix.empty() || b.prefix.empty() || !normSet( pre, kMaxAffixSet ) || pre.size() > kMaxAffixSet ) r.prefix.clear();
        else r.prefix = std::move( pre );
    }
    // suffix union
    {
        std::vector<std::string> suf = a.suffix;
        for( const std::string& s : b.suffix ) suf.push_back( s );
        if( a.suffix.empty() || b.suffix.empty() || !normSet( suf, kMaxAffixSet ) || suf.size() > kMaxAffixSet ) r.suffix.clear();
        else r.suffix = std::move( suf );
    }
    return r;
}

// STAR r = a* : zero-or-more — can match "" (so canEmpty) and imposes NO required trigram (zero copies
// means no byte need appear). Sound result: ALL, empty prefix/suffix, exact unknown. (Cox: star ⇒ match
// of the child but as a *requirement* it's empty; we conservatively use ALL.) PLUS r = a+ delegates to the
// child's match (≥1 copy ⇒ the child's required trigrams must appear) but loses exact/affix precision.
inline RegexInfo riStar( RegexInfo /*child*/ )
{
    RegexInfo r; r.canEmpty = true; r.exactKnown = false; r.match = TriQuery::all(); return r;
}
inline RegexInfo riPlus( RegexInfo child )
{
    dropExact( child );
    RegexInfo r; r.canEmpty = child.canEmpty; r.exactKnown = false; r.match = std::move( child.match ); return r;   // ≥1 copy ⇒ child trigrams required
}
inline RegexInfo riQuest( RegexInfo /*child*/ )   // a? : zero-or-one ⇒ optional ⇒ no required trigram (ALL)
{
    RegexInfo r; r.canEmpty = true; r.exactKnown = false; r.match = TriQuery::all(); return r;
}

// finish a top-level RegexInfo: if it is still an exact set, fold its strings' trigram AND/OR into `match`
// (a fully-literal regex like `Foo` or `(ab|cd)` becomes a precise trigram query here). Returns the final
// query. Always sound: an exact set with a <3-char member yields ALL for that alternative.
inline TriQuery finishQuery( RegexInfo r )
{
    if( r.exactKnown )
        return andOf( std::move( r.match ), triQueryOfStringSet( r.exact ) );
    return std::move( r.match );
}

// ── A small recursive-descent parser for the ECMAScript-subset we analyze ──────────────────────────
//
// Grammar (precedence low→high):  alt := concat ('|' concat)*   concat := repeat*   repeat := atom quant?
//   atom := '(' alt ')' | '[' class ']' | '.' | '^' | '$' | '\' escaped | literalChar
//   quant := '*' | '+' | '?' | '{' n (',' m?)? '}'
// Anything we don't model precisely (backrefs, lookarounds, unicode props, complex classes) degrades to
// riAnyChar()/ALL — SOUND. The parser builds RegexInfo directly (no separate AST node type needed). It is
// PREFILTER-ONLY: precision of this parse never affects correctness, because std::regex re-verifies.
class RegexAnalyzer
{
public:
    explicit RegexAnalyzer( const std::string& pat ) : s_( pat ) {}

    // Parse the whole pattern → the sound trigram query. On any parse shortfall we are conservative (ALL).
    TriQuery analyze()
    {
        pos_ = 0;
        RegexInfo r = parseAlt();
        // trailing unparsed input (shouldn't happen for valid regex) ⇒ be safe
        if( pos_ != s_.size() ) return TriQuery::all();
        return finishQuery( std::move( r ) );
    }

private:
    const std::string& s_;
    std::size_t        pos_ = 0;

    bool   eof()  const { return pos_ >= s_.size(); }
    char   peek() const { return s_[ pos_ ]; }
    char   next()       { return s_[ pos_++ ]; }

    RegexInfo parseAlt()
    {
        RegexInfo left = parseConcat();
        while( !eof() && peek() == '|' )
        {
            next();                              // consume '|'
            RegexInfo right = parseConcat();
            left = riAlternate( std::move( left ), std::move( right ) );
        }
        return left;
    }

    RegexInfo parseConcat()
    {
        RegexInfo acc = riEmpty();
        bool      any = false;
        while( !eof() && peek() != '|' && peek() != ')' )
        {
            const std::size_t before = pos_;
            RegexInfo piece = parseRepeat();
            acc = any ? riConcat( std::move( acc ), std::move( piece ) ) : std::move( piece );
            any = true;
            if( pos_ == before ) break;   // no progress on malformed input (e.g. unterminated `a{2,`): stop —
                                          // analyze() then sees pos_ != size and returns ALL (sound full-scan).
        }
        return any ? acc : riEmpty();
    }

    RegexInfo parseRepeat()
    {
        RegexInfo atom = parseAtom();
        if( eof() ) return atom;
        const char c = peek();
        if( c == '*' ) { next(); return riStar(  std::move( atom ) ); }
        if( c == '+' ) { next(); return riPlus(  std::move( atom ) ); }
        if( c == '?' ) { next(); return riQuest( std::move( atom ) ); }
        if( c == '{' )                                   // bounded/unbounded repetition {n}, {n,}, {n,m}
        {
            // We don't model the exact count for the prefilter — treat {0,*}/{1,*} soundly:
            //   {0,...} or {n,...} with n==0 ⇒ optional ⇒ ALL; {n,...} with n>=1 ⇒ child trigrams required.
            const std::size_t save = pos_;
            next();                                      // consume '{'
            long lo = 0; bool sawLo = false;
            while( !eof() && std::isdigit( (unsigned char)peek() ) ) { lo = lo * 10 + ( next() - '0' ); sawLo = true; }
            // skip to closing '}' (we only need lo's zero-ness)
            while( !eof() && peek() != '}' ) next();
            if( !eof() && peek() == '}' ) next();
            else { pos_ = save; return atom; }           // malformed → treat '{' as a literal atom already parsed
            if( sawLo && lo >= 1 ) return riPlus( std::move( atom ) );   // ≥1 mandatory copy
            return riQuest( std::move( atom ) );                         // 0 mandatory copies ⇒ optional
        }
        return atom;
    }

    RegexInfo parseAtom()
    {
        const char c = peek();
        if( c == '(' )
        {
            next();                                      // consume '('
            // skip a non-capturing / lookaround prefix "(?...":   (?:  (?=  (?!  (?<=  (?<!
            if( !eof() && peek() == '?' )
            {
                // lookarounds are zero-width assertions for matching; for INDEXING treat the whole group as
                // ε (anchor-like) — sound, since we can't rely on its content appearing literally.
                // Consume to the matching ')'.
                int depth = 1; next();                   // consume '?'
                while( !eof() && depth > 0 ) { char d = next(); if( d == '(' ) ++depth; else if( d == ')' ) --depth; else if( d == '\\' && !eof() ) next(); }
                return riAnchor();
            }
            RegexInfo inner = parseAlt();
            if( !eof() && peek() == ')' ) next();        // consume ')'
            return inner;
        }
        if( c == '[' ) return parseClass();
        if( c == '.' ) { next(); return riAnyChar(); }
        if( c == '^' || c == '$' ) { next(); return riAnchor(); }
        if( c == '\\' )
        {
            next();                                      // consume '\'
            if( eof() ) return riAnchor();
            const char e = next();
            // word/space/digit classes and boundaries → unknown char or anchor (sound)
            if( e == 'b' || e == 'B' || e == 'A' || e == 'Z' || e == 'z' ) return riAnchor();
            if( e == 'w' || e == 'W' || e == 'd' || e == 'D' || e == 's' || e == 'S' ) return riAnyChar();
            // an escaped metacharacter / ordinary char → that literal byte
            return riLiteral( std::string( 1, unescape( e ) ) );
        }
        if( c == ')' || c == '|' ) return riEmpty();     // shouldn't reach here (caller guards), be safe
        // ordinary literal char — but greedily absorb a RUN of ordinary chars NOT followed by a quantifier
        // that would bind only the last char. We must stop the run before a char that has a quantifier,
        // because `abc*` means `ab` then `c*` (the * binds only `c`). So peek the NEXT char's quantifier.
        std::string run;
        while( !eof() )
        {
            const char ch = peek();
            if( std::strchr( ".[](){}|^$\\*+?", ch ) != nullptr ) break;   // a metachar ends the literal run
            // if the char AFTER ch is a quantifier, ch must be its own atom — stop the run before ch
            // (unless run is empty, in which case ch IS this atom and we let the run hold just ch).
            const bool nextIsQuant = ( pos_ + 1 < s_.size() ) && std::strchr( "*+?{", s_[ pos_ + 1 ] ) != nullptr;
            if( nextIsQuant && !run.empty() ) break;
            run += ch; next();
            if( nextIsQuant ) break;                      // ch is a single-char atom that a quantifier will bind
        }
        return riLiteral( run );
    }

    // [...] character class. We ENUMERATE only simple positive classes of literal chars / short ranges into
    // a small exact set; negated `[^...]`, large ranges, or class-escapes degrade to riAnyChar() (ALL).
    RegexInfo parseClass()
    {
        next();                                          // consume '['
        if( !eof() && peek() == '^' )                    // negated class — unknown byte, sound
        {
            // consume to closing ']'
            while( !eof() && peek() != ']' ) { if( peek() == '\\' ) { next(); if( !eof() ) next(); } else next(); }
            if( !eof() ) next();
            return riAnyChar();
        }
        std::vector<std::string> chars;
        bool degrade = false;
        while( !eof() && peek() != ']' )
        {
            char lo;
            if( peek() == '\\' ) { next(); if( eof() ) { degrade = true; break; } char e = next(); if( std::strchr( "wWdDsS", e ) ) { degrade = true; } lo = unescape( e ); }
            else lo = next();
            if( !eof() && peek() == '-' && pos_ + 1 < s_.size() && s_[ pos_ + 1 ] != ']' )   // a range lo-hi
            {
                next();                                  // consume '-'
                char hi = ( peek() == '\\' ) ? ( next(), unescape( next() ) ) : next();
                if( hi < lo || ( hi - lo ) > 6 ) degrade = true;            // wide range ⇒ don't enumerate (ALL)
                else for( char ch = lo; ch <= hi; ++ch ) chars.push_back( std::string( 1, ch ) );
            }
            else if( !degrade ) chars.push_back( std::string( 1, lo ) );
            if( chars.size() > kMaxExactSet ) degrade = true;
        }
        if( !eof() ) next();                             // consume ']'
        if( degrade || chars.empty() || chars.size() > kMaxExactSet ) return riAnyChar();
        return riCharSet( std::move( chars ) );
    }

    // map an escaped char to its literal byte (the common ones); default = the char itself.
    static char unescape( char e )
    {
        switch( e ) { case 'n': return '\n'; case 't': return '\t'; case 'r': return '\r'; case 'f': return '\f'; case 'v': return '\v'; case '0': return '\0'; default: return e; }
    }
};

// Evaluate a TriQuery against ONE file's bytes → "could this file match?". This replaces the posting-list
// evaluator: with no index, the question "is trigram T in file F" is answered by searching F's bytes for
// the 3-byte string directly (a memchr-driven substring find — a fraction of the cost of having built a
// posting list for every trigram in the corpus). Semantics are IDENTICAL to the old evalTriQuery restricted
// to one file: ALL ⇒ true (full-scan fallback), NONE ⇒ false, And ⇒ every child (empty And ⇒ true, the
// AND-identity), Or ⇒ any child (empty Or ⇒ false, the OR-identity), Trigram ⇒ the file contains it. And
// short-circuits, so the common case is one rejected trigram and one pass over the file.
inline bool triQueryMatchesText( const TriQuery& q, std::string_view text ) noexcept
{
    switch( q.op )
    {
        case TriQuery::Op::All:  return true;
        case TriQuery::Op::None: return false;
        case TriQuery::Op::Trigram:
        {
            const char probe[3] = { char( ( q.tri >> 16 ) & 0xFF ), char( ( q.tri >> 8 ) & 0xFF ), char( q.tri & 0xFF ) };
            return text.find( std::string_view( probe, 3 ) ) != std::string_view::npos;
        }
        case TriQuery::Op::And:
            for( const TriQuery& k : q.kids ) if( !triQueryMatchesText( k, text ) ) return false;
            return true;
        case TriQuery::Op::Or:
            for( const TriQuery& k : q.kids ) if(  triQueryMatchesText( k, text ) ) return true;
            return false;
    }
    return true;   // unreachable; ALL (keep the file) is the SOUND default
}

// ripgrep-style context lines (--grep-context/-before/-after). `lineStarts` is the ascending byte-offset
// of the start of every line in `s` (line 1 at lineStarts[0], etc — the same one-pass split grepHits
// already needs for line numbering, computed once per file and reused per hit rather than rescanned).
// Returns the raw text of the `count` lines strictly before/after `line` (1-based), newline-joined, no
// trailing newline, CLAMPED to [1,lineCount] (a hit on line 1 with before-context ⇒ empty string, never
// OOB). UTF-8-safe: back off any continuation byte at the cut edges — same rule as serialize.h's
// sliceBodyLines (line splits are on '\n', always a codepoint boundary, so this is normally a no-op; kept
// as the same defensive back-off in case of a corrupt/binary file slipping past ingest).
// lineStarts[i] is the byte offset AFTER the i-th '\n' (plus a leading 0), so a file ending in '\n' yields
// one phantom trailing entry equal to s.size() — an empty "line" nothing ever matches on (the hit-line
// numbering in grepHits' lineAt never reports it). Drop it so the count reflects REAL lines only; otherwise
// --grep-after on the true last content line would emit that phantom empty line instead of correctly
// clamping to "no after-context".
inline std::uint32_t grepRealLineCount( const std::string& s, const std::vector<std::size_t>& lineStarts ) noexcept
{
    std::uint32_t lineCount = std::uint32_t( lineStarts.size() );
    if( lineCount > 0 && lineStarts[ lineCount - 1 ] == s.size() && !s.empty() && s.back() == '\n' ) --lineCount;
    return lineCount;
}

// Raw text of the INCLUSIVE 1-based line range [loLine,hiLine], newline-joined, no trailing newline. The
// one slicing core shared by the context blocks and by the matched line itself, so the two can never drift
// apart on the EOF / UTF-8 edges. Caller has already clamped loLine/hiLine into [1,lineCount].
inline std::string grepLineRangeText( const std::string& s, const std::vector<std::size_t>& lineStarts,
                                      std::uint32_t lineCount, std::uint32_t loLine, std::uint32_t hiLine )
{
    // byteEnd for the LAST real line must exclude a trailing '\n' too (that's the phantom-line's newline,
    // trimmed out of lineCount but still physically present in `s` — without this, --grep-after=N that
    // reaches the true last line would emit one extra blank line at the end).
    const std::size_t byteStart = lineStarts[ loLine - 1 ];
    const std::size_t byteEnd   = ( hiLine < lineCount ) ? ( lineStarts[ hiLine ] - 1 )                 // exclude hiLine's trailing '\n'
                                 : ( !s.empty() && s.back() == '\n' ) ? s.size() - 1 : s.size();        // last real line: to end of file, minus its own trailing '\n' if any
    // UTF-8 boundary back-off, same rule as serialize.h's truncateUtf8WithEllipsis: a cut is mid-sequence
    // exactly when the byte AT the cut is a continuation byte, so back off WHILE that holds and stop on the
    // first lead/ASCII byte. The old form tested s[be-1] instead and therefore walked off the END of a
    // COMPLETE sequence — a context line ending in "—" (0xE2 0x80 0x94) lost both continuation bytes and
    // was emitted as a lone 0xE2, which is not valid UTF-8 and killed `xmllint --noout` (G4) from inside
    // CDATA. `be == s.size()` is a boundary by definition, hence the `be < s.size()` guard.
    std::size_t bs = byteStart, be = byteEnd;
    if( be > s.size() ) be = s.size();          // defensive (shouldn't happen: lineStarts derived from s)
    while( bs < be && ( static_cast<unsigned char>( s[bs] ) & 0xC0 ) == 0x80 ) ++bs;         // skip into the first whole codepoint
    while( be > bs && be < s.size() && ( static_cast<unsigned char>( s[be] ) & 0xC0 ) == 0x80 ) --be;   // cut only ON a boundary
    return s.substr( bs, be - bs );
}

inline std::string grepContextSlice( const std::string& s, const std::vector<std::size_t>& lineStarts, std::uint32_t line, int count, bool before )
{
    if( count <= 0 ) return {};
    const std::uint32_t lineCount = grepRealLineCount( s, lineStarts );
    if( line < 1 || line > lineCount ) return {};   // degrade: out-of-range hit line ⇒ no context, never OOB

    std::uint32_t lo, hi;   // inclusive 1-based line range to emit
    if( before )
    {
        if( line == 1 ) return {};                                    // clamp at file start: 0 before-lines
        hi = line - 1;
        lo = ( hi > std::uint32_t( count ) ) ? hi - std::uint32_t( count ) + 1 : 1;
    }
    else
    {
        if( line >= lineCount ) return {};                            // clamp at file end: 0 after-lines
        lo = line + 1;
        const std::uint32_t want = lo + std::uint32_t( count ) - 1;
        hi = ( want < lineCount ) ? want : lineCount;
    }
    return grepLineRangeText( s, lineStarts, lineCount, lo, hi );
}

// A single minified/generated line can be megabytes; the matched line is emitted for EVERY hit, so it is
// capped (ripgrep does the same). The cut backs off any UTF-8 continuation byte so the emitted text is
// always valid UTF-8 — G4 depends on it. Chosen wide enough that a normal source line is never touched.
inline constexpr std::size_t kGrepMatchedLineMaxBytes = 512;

// The MATCHED line itself (P5): the text the agent actually searched for, which neither the bare hit nor
// the before/after blocks ever showed. Empty when the hit line is out of range (degrade, never OOB).
inline std::string grepMatchedLine( const std::string& s, const std::vector<std::size_t>& lineStarts, std::uint32_t line )
{
    const std::uint32_t lineCount = grepRealLineCount( s, lineStarts );
    if( line < 1 || line > lineCount ) return {};
    std::string text = grepLineRangeText( s, lineStarts, lineCount, line, line );
    if( text.size() > kGrepMatchedLineMaxBytes )
    {
        std::size_t cut = kGrepMatchedLineMaxBytes;
        while( cut > 0 && ( static_cast<unsigned char>( text[cut] ) & 0xC0 ) == 0x80 ) --cut;   // never split a codepoint
        text.resize( cut );
    }
    return text;
}

// One un-enriched match WITHIN a file: 1-based line + the byte offset the match starts at. This is all a
// scanning worker produces (8 B, POD) — the owning file is the slot index, and the strings (enclosing
// chain, matched line, context) are built later, only for the matches that survive the budget, so a common
// pattern over a big tree never materializes megabytes of text it is about to throw away.
struct GrepMatchSite { std::uint32_t line; std::uint32_t byteOffset; };
static_assert( sizeof( GrepMatchSite ) == 8, "GrepMatchSite must stay an 8-byte POD" );

// The same match once its file is known — what the budget-truncated, path-sorted list holds.
struct GrepRawHit { std::uint32_t fileId; std::uint32_t line; std::uint32_t byteOffset; };
static_assert( sizeof( GrepRawHit ) == 12, "GrepRawHit must stay a 12-byte POD" );

// Scan ONE file's bytes for `pat` (literal, re == nullptr) or `re` (regex), appending at most `hitCapCount`
// sites to `out`. Pure function of (text, pattern) — no shared state — which is what makes the caller's
// parallel fan-out deterministic. Matches arrive in ascending position, so newlines are counted only over
// the gap since the previous match (rescanning from byte 0 per hit made hit-dense large files O(hits×size)).
//
// §A0 — hitCapCount is a std::size_t, and every budget/window quantity on this path is 64-bit for the same
// reason: the cap used to be an `int` derived from `cap * 4`, so `--limit=536870912` overflowed the product
// NEGATIVE, collected nothing, and the release binary reported hits="0" hits_capped="0" at exit 0 — a
// confident false zero. There is no int arithmetic left between the CLI value and this comparison.
inline void grepScanText( const std::string& text, const std::string& pat,
                          const std::regex* re, std::size_t hitCapCount, std::vector<GrepMatchSite>& out )
{
    std::uint32_t line    = 1;
    std::size_t   scanned = 0;
    const auto    lineAt  = [ & ]( std::size_t pos ) noexcept
    { for( std::size_t i = scanned; i < pos; ++i ) if( text[i] == '\n' ) ++line; scanned = pos; return line; };

    if( re != nullptr )
    {
        // std::sregex_iterator can throw regex_error (error_complexity/error_space) mid-scan on a
        // catastrophic-backtracking pattern over a pathological file — construction succeeded (the pattern
        // itself compiled fine), the blowup happens during matching. Only construction was guarded before
        // this (A4-F10); an uncaught throw here reached std::terminate and killed the whole run over one
        // bad file. Degrade: keep this file's hits so far and move on to the next file.
        try
        {
            for( auto it = std::sregex_iterator( text.begin(), text.end(), *re ); it != std::sregex_iterator(); ++it )
            {
                const std::size_t pos = std::size_t( it->position() );
                out.push_back( { lineAt( pos ), std::uint32_t( pos ) } );
                if( out.size() >= hitCapCount ) break;
            }
        }
        catch( const std::regex_error& )
        {
            DEGRADED_PATH_ALERT( "grep: regex match blew up (catastrophic backtracking?) — file skipped" );
        }
    }
    else
    {
        std::size_t pos = text.find( pat );
        while( pos != std::string::npos )
        {
            out.push_back( { lineAt( pos ), std::uint32_t( pos ) } );
            if( out.size() >= hitCapCount ) break;
            pos = text.find( pat, pos + 1 );
        }
    }
}

// §P0.4 — does the user's --regex pattern COMPILE? An invalid pattern is a user error, not a measurement:
// `--regex='(fnv1a'` used to return hits="0" at exit 0 with an empty stderr, byte-identical to a true
// negative on every channel. Returns the engine's diagnostic when the pattern is invalid, nullopt when it
// compiles, so the CLI seam can refuse before any scanning happens.
//
// This is deliberately the VERIFIER's compile — the one whose failure means "your pattern is invalid". The
// trigram PREFILTER's parse (RegexAnalyzer, see the note at the top of that section) is allowed to fail and
// degrade: it only ever widens the candidate set, so its imprecision cannot change a result. Refusing here,
// ahead of both paths, is also why --no-prefilter refuses identically.
inline std::optional<std::string> regexCompileError( const std::string& pat )
{
    try                                { const std::regex probe( pat, std::regex::ECMAScript | std::regex::optimize ); (void)probe; }
    catch( const std::regex_error& e ) { return std::string( e.what() ); }
    catch( ... )                       { return std::string( "invalid regular expression" ); }
    return std::nullopt;
}

// regex=false → literal substring; regex=true → ECMAScript regex. Every ingested file is read and scanned
// once, in parallel; for regex, a file is handed to the std::regex verifier only if the sound Russ-Cox
// trigram query derived from the pattern is satisfied by its bytes, and noPrefilter forces the full-scan
// oracle (every file) so the gate can prove prefiltered == full-scan. The prefilter only changes WHICH
// files the verifier opens, never which lines are kept.
// grepEnrich()'s ctxBefore/ctxAfter (default 0) request N ripgrep-style context lines around each hit
// (--grep-context/-before/-after); default 0 ⇒ GrepHit::before/after stay empty. GrepHit::text (the
// matched line) is always filled — it is the point of a search result.
//
// DETERMINISM (a hard law, and this is a parallel path): the workers write into per-file slots they alone
// own, and NOTHING downstream depends on the order in which files finished. The budget is applied AFTER
// the fan-out, in ascending fileId order — exactly the order the old serial candidate loop consumed —
// so which hits survive a truncation is a pure function of the corpus, never of thread scheduling.
//
// §P11.1 — the returned ORDER is TIER-then-path, not path alone. Plain path-alphabetical order plus the
// caller's fixed row cap is a systematic bias against code on any doc-bearing repo: on ripwire's own tree
// `--grep=DEGRADED_PATH_ALERT` filled 66 of its 100 shown rows with markdown and left no `test/` row at all,
// because `AGENTS.md` and `AUDIT*.md` sort above `src/` and the cap always cuts the tail. Ordering HERE
// rather than in the emitter keeps the CLI verb and the MCP `grep` verb on ONE order — they already share
// this collection precisely so they cannot diverge. Path-alphabetical survives untouched INSIDE a tier, so
// a file's hits stay contiguous, which pass 4's one-read-per-file caching depends on.
//
// §A1 — the collection budget is a FIXED CEILING and no longer scales with the caller's page window. It
// used to be `cap * 4` with `cap = max(100, offset + limit)`: collection stopped mid-tree in ascending
// fileId order, the tier-then-path sort ran over whatever that happened to admit, and so EVERY page was a
// window into a differently-ranked list. Walking `--limit=100` pages over a 1173-hit pattern never served 59
// rows and served 59 others twice, and `total=` GREW as the offset advanced. Nothing the caller passes may
// influence WHAT is collected — that is the whole invariant, and it is why the row cap is not a parameter of
// grepCollect() at all. This ceiling is the one the pre-fix `--limit=1000000` run already reached, so a
// run that asked for everything is unchanged; hits_capped="1" keeps its meaning (ceiling reached ⇒ the
// reported hits= is a FLOOR).
inline constexpr std::size_t kGrepCollectionBudget = 4000000;

// The whole tier-then-path-ordered raw hit list plus the one bit the emitter must disclose. Split from the
// enrichment (below) because a common pattern collects ~10^6 raw hits over a repo this size: at 12 B each
// that is cheap, while materializing every hit's matched line, context and enclosing chain is not — and the
// caller only ever PRINTS a window of them.
struct GrepCollection { std::vector<GrepRawHit> raw; bool isBudgetReached; };

inline GrepCollection grepCollect( const IngestResult& ing, const std::string& pat, bool regex = false, bool noPrefilter = false )
{
    const std::uint32_t fileCount   = std::uint32_t( ing.files.size() );
    const std::size_t   budgetCount = kGrepCollectionBudget;
    if( fileCount == 0 ) return {};

    // a pattern that doesn't compile is a user error, not a degrade — the CLI seam refuses it before we are
    // called (regexCompileError above). Kept as a belt-and-braces early REJECT for library/MCP callers that
    // did not ask; each worker compiles its own copy so no std::regex object is shared.
    if( regex ) { try { const std::regex probe( pat, std::regex::ECMAScript | std::regex::optimize ); (void)probe; } catch( ... ) { return {}; } }

    // the sound regex→trigram query, computed once and evaluated per file (read-only across workers)
    const TriQuery prefilterQuery = ( regex && !noPrefilter ) ? RegexAnalyzer( pat ).analyze() : TriQuery::all();

    // ── pass 1: parallel scan, one worker per hardware thread, one file at a time ──────────────────────
    std::vector<std::vector<GrepMatchSite>> perFileSites( fileCount );   // slot f written by exactly one worker
    std::atomic<std::uint32_t>              nextFileId { 0 };
    const auto                              fileWorker = [ & ]
    {
        std::regex reLocal;
        if( regex ) { try { reLocal = std::regex( pat, std::regex::ECMAScript | std::regex::optimize ); } catch( ... ) { return; } }
        std::string text;
        try
        {
            for( std::uint32_t f = nextFileId.fetch_add( 1 ); f < fileCount; f = nextFileId.fetch_add( 1 ) )
            {
                text.clear();
                // unreadable file ⇒ degrade to empty bytes and keep going (what the index build did too:
                // it left an empty `contents` entry rather than dropping the file from the corpus).
                if( !docparse::detail::readWholeFile( diskPath( ing, f ), text ) ) text.clear();
                if( regex && !noPrefilter && !triQueryMatchesText( prefilterQuery, text ) ) continue;
                grepScanText( text, pat, regex ? &reLocal : nullptr, budgetCount, perFileSites[f] );
            }
        }
        catch( ... )   // a throw escaping a worker thread is std::terminate — degrade to partial hits instead
        {
            DEGRADED_PATH_ALERT( "grep: scan worker degraded (exception swallowed) — partial hit set" );
        }
    };
    {
        // symmetric bare scope: the workers live exactly as long as the scan
        const unsigned    hwThreadCount = std::thread::hardware_concurrency();
        const std::size_t workerCount   = std::min<std::size_t>( { hwThreadCount ? hwThreadCount : 1u, fileCount, 16 } );
        if( workerCount <= 1 ) fileWorker();
        else
        {
            std::vector<std::thread> workers;
            workers.reserve( workerCount );
            for( std::size_t w = 0; w < workerCount; ++w ) workers.emplace_back( fileWorker );
            for( std::thread& worker : workers ) worker.join();
        }
    }

    // ── pass 2: apply the budget in ascending fileId order (thread-order-independent) ──────────────────
    std::vector<GrepRawHit> raw;
    for( std::uint32_t f = 0; f < fileCount && raw.size() < budgetCount; ++f )
        for( const GrepMatchSite& site : perFileSites[f] )
        {
            raw.push_back( { f, site.line, site.byteOffset } );
            if( raw.size() >= budgetCount ) break;
        }

    // §P11.1: the canonical order is TIER-then-path (see this function's header comment). The key is
    // materialized ONCE PER FILE, not evaluated inside the comparator: pathTierOf() lowercases an extension
    // into a fresh std::string, and with the §A1 ceiling this list is ~10^6 rows — O(n log n) calls to it
    // would allocate millions of times. fileRank is a dense position in the tier-then-path order, so the
    // comparator below is pure integer work and a file's hits stay contiguous (pass 4's one-read-per-file
    // caching depends on that).
    std::vector<std::uint32_t> hitFileIds;
    hitFileIds.reserve( fileCount );
    {
        std::vector<char> fileHasHitsForRank( fileCount, 0 );
        for( const GrepRawHit& h : raw ) fileHasHitsForRank[ h.fileId ] = 1;
        for( std::uint32_t f = 0; f < fileCount; ++f ) if( fileHasHitsForRank[f] ) hitFileIds.push_back( f );
    }
    std::sort( hitFileIds.begin(), hitFileIds.end(), [ & ]( std::uint32_t a, std::uint32_t b )
               {
                   const PathTier ta = pathTierOf( ing.files[a] ), tb = pathTierOf( ing.files[b] );
                   if( ta != tb ) return ta < tb;
                   return ing.files[a] < ing.files[b];
               } );
    std::vector<std::uint32_t> fileRank( fileCount, UINT32_MAX );
    for( std::uint32_t rankIndex = 0; rankIndex < std::uint32_t( hitFileIds.size() ); ++rankIndex ) fileRank[ hitFileIds[ rankIndex ] ] = rankIndex;

    std::sort( raw.begin(), raw.end(), [ & ]( const GrepRawHit& a, const GrepRawHit& b )
               {
                   if( fileRank[ a.fileId ] != fileRank[ b.fileId ] ) return fileRank[ a.fileId ] < fileRank[ b.fileId ];
                   if( a.line != b.line )                             return a.line < b.line;
                   return a.byteOffset < b.byteOffset;                // total order: two hits on ONE line stay in scan order
               } );

    // read the bit BEFORE the move — a braced-init-list is evaluated left to right, so `raw.size()` after
    // `std::move( raw )` would read a moved-from vector and always report "not capped"
    const bool isBudgetReached = raw.size() >= budgetCount;
    return { std::move( raw ), isBudgetReached };
}

// Turn a WINDOW of already-collected, already-ordered raw hits into printable rows: enclosing-symbol chain,
// the matched line, and the optional ripgrep-style context lines. `window` is a view into a
// grepCollect() result the caller still owns (views at seams); it must be a contiguous slice of that
// ordered list, which is what keeps one file's hits adjacent and the per-file text read amortized.
inline std::vector<GrepHit> grepEnrich( const IngestResult& ing, std::span<const GrepRawHit> window, int ctxBefore = 0, int ctxAfter = 0 )
{
    const std::uint32_t fileCount = std::uint32_t( ing.files.size() );
    if( fileCount == 0 || window.empty() ) return {};
    const std::span<const GrepRawHit> raw = window;

    // ── pass 3: enclosing-symbol index, built ONLY for the windowed files that actually have hits ──────
    std::vector<char> fileHasHits( fileCount, 0 );
    for( const GrepRawHit& h : raw ) fileHasHits[ h.fileId ] = 1;
    std::vector<std::vector<NodeId>> fileSyms( fileCount );                  // per file, sorted by sigStartByte
    for( const Symbol& s : ing.symbols ) if( s.fileId < fileCount && fileHasHits[ s.fileId ] ) fileSyms[ s.fileId ].push_back( s.id );
    for( std::uint32_t f = 0; f < fileCount; ++f )
        if( fileHasHits[f] )
            std::sort( fileSyms[f].begin(), fileSyms[f].end(), [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
    const auto enclosing = [ & ]( std::uint32_t f, std::uint32_t off ) -> const Symbol*
    {
        const Symbol* best = nullptr;
        for( NodeId id : fileSyms[f] )
        {
            const Symbol& s = ing.symbols[id];
            if( s.sigStartByte > off ) break;
            if( off < s.endByte && ( !best || s.sigStartByte > best->sigStartByte ) ) best = &s;
        }
        return best;
    };

    // grep-ast breadcrumb (Wave 4 #4): report the FULL enclosing-scope chain, not just the innermost
    // symbol's bare name — `ns::Class::method` reads like a stack frame instead of a lone leaf. The data
    // already exists on the ingested Symbol (Symbol::scope, model.h): the enclosing class/namespace name,
    // captured at ingest for canonical scope::name resolution (see resolve.h's canonicalId — same
    // scope+"::"+name join, minus the file-path prefix that canonicalId adds for cross-file identity;
    // a grep breadcrumb only needs to disambiguate WITHIN the hit's own file/enclosing symbol). No AST
    // walk here — enclosing() already found the innermost def; scope is just richer when it's a method.
    // ── pass 4: enrich the survivors (matched line, context lines, breadcrumb) ─────────────────────────
    // Text comes from a RE-READ of the hit's file rather than from a retained whole-corpus buffer: `raw` is
    // the caller's WINDOW (one page), so this touches at most that many distinct files (a handful in
    // practice) instead of the 863 MB the old GrepIndex::contents pinned for the entire corpus. The window
    // is a contiguous slice of the tier-then-path order, so a file's hits are contiguous — one read + one
    // lineStarts build per file, cached hit-to-hit exactly as before.
    std::uint32_t            loadedFileId = UINT32_MAX;
    std::string              fileText;
    std::vector<std::size_t> lineStarts;
    const auto ensureFileLoaded = [ & ]( std::uint32_t f )
    {
        if( f == loadedFileId ) return;
        loadedFileId = f;
        fileText.clear();
        if( !docparse::detail::readWholeFile( diskPath( ing, f ), fileText ) ) fileText.clear();   // degrade: no text, never a crash
        lineStarts.clear();
        lineStarts.push_back( 0 );
        for( std::size_t i = 0; i < fileText.size(); ++i ) if( fileText[i] == '\n' ) lineStarts.push_back( i + 1 );
    };

    std::vector<GrepHit> hits;
    hits.reserve( raw.size() );
    for( const GrepRawHit& r : raw )
    {
        const Symbol* e = enclosing( r.fileId, r.byteOffset );
        std::string   chain;
        if( e ) chain = e->scope.empty() ? e->name : ( e->scope + "::" + e->name );
        GrepHit h{ r.fileId, r.line, std::move( chain ), {}, {}, {} };
        ensureFileLoaded( r.fileId );
        h.text = grepMatchedLine( fileText, lineStarts, r.line );
        if( ctxBefore > 0 ) h.before = grepContextSlice( fileText, lineStarts, r.line, ctxBefore, /*before=*/true );
        if( ctxAfter  > 0 ) h.after  = grepContextSlice( fileText, lineStarts, r.line, ctxAfter,  /*before=*/false );
        hits.push_back( std::move( h ) );
    }
    return hits;
}

// collect + enrich in one call, for the callers that only ever want the FIRST `cap` rows of the ordered
// list and need no total (the MCP `grep` verb). `cap` is a ROW cap and nothing else — it cannot reach the
// collection budget, which is exactly the §A1 invariant. The CLI verb calls the two halves separately
// because it must disclose a total and a window that the row cap does not describe.
inline std::vector<GrepHit> grepHits( const IngestResult& ing, const std::string& pat, int cap, bool regex = false, bool noPrefilter = false, int ctxBefore = 0, int ctxAfter = 0 )
{
    const GrepCollection collected = grepCollect( ing, pat, regex, noPrefilter );
    const std::size_t    rowCount  = std::min<std::size_t>( collected.raw.size(), cap > 0 ? std::size_t( cap ) : 100 );
    return grepEnrich( ing, std::span<const GrepRawHit>( collected.raw ).first( rowCount ), ctxBefore, ctxAfter );
}

}   // namespace ctx
