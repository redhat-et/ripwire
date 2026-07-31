// clonelex_harness.cpp — unit + mutation harness for the clone NORMALIZER's apostrophe/comment lexing
// (src/clones.h, A4-F2 fix) and the O(1) keyword membership (A4-P3). clones.h is header-only, so this
// calls normalizeSpan()/normalizeTokens()/cloneIsKeyword() directly and asserts the exact token stream —
// far more precise than an end-to-end --clones diff, and independent of the ctxpack binary + main.cpp.
//
// The bug (A4-F2): ' unconditionally opened a "char literal" scanned to the next ' — so a Rust lifetime
// ('a), a C++14 digit separator (1'000'000), or an apostrophe in a Python `#` comment (don't) swallowed
// the rest of the body into one $S token, producing false Type-1/2 clones AND false negatives.
//
// Cases proved (each maps to a fix clause):
//   F2-a  Rust lifetime `'a` != a real char literal `'a'`  — lifetime is punctuation, char literal is $S.
//   F2-b  C++14 digit separator 1'000'000 → a single $N    — number scanner absorbs the separator.
//   F2-c  real char literals ('x' '\n' '\\' '\xNN' '\0')   → each one $S (fix must not over-correct).
//   F2-d  ' right after an identifier/digit byte            → punctuation (never opens a literal).
//   F2-e  two DIFFERENT bodies whose only difference sits AFTER an unpaired ' normalize DIFFERENTLY
//         (the swallow no longer collapses them — the core false-clone repro, at token level).
//   F2-f  Python/shell `#` line comments (incl. a contraction) are dropped when stripHashComments=true,
//         and are NOT dropped when false (C/C++ keep `#`, e.g. preprocessor, as punctuation).
//   P3    cloneIsKeyword membership still correct (hash set replacing the linear scan).
//   MUT   a mutation self-test: the char-literal vs lifetime streams MUST differ (flip ⇒ gate fails).
//
// normalizeSpan and normalizeTokens share the lexer; both are asserted so a future edit to one is caught.
// Exit 0 = all pass; nonzero = a failure (message on stderr).

#include "../src/clones.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace ctx;

static int g_fail = 0;
static void check( bool cond, const char* msg )
{
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", msg );
    if( !cond ) g_fail = 1;
}

// normalizeSpan over the whole string; returns the joined token stream (trailing space trimmed) + count.
static std::pair<std::string, std::uint32_t> norm( const std::string& s, bool stripHash = false )
{
    std::uint32_t tc = 0;
    std::string   out = normalizeSpan( s, 0, std::uint32_t( s.size() ), tc, stripHash );
    if( !out.empty() && out.back() == ' ' ) out.pop_back();
    return { out, tc };
}
// normalizeTokens over the whole string; join with single spaces so it can be compared to norm()'s stream.
static std::string toks( const std::string& s, bool stripHash = false )
{
    std::vector<std::string> v = normalizeTokens( s, 0, std::uint32_t( s.size() ), stripHash );
    std::string out;
    for( std::size_t i = 0; i < v.size(); ++i ) { if( i ) out += ' '; out += v[i]; }
    return out;
}

int main()
{
    // ── F2-a — Rust lifetime `'a` is NOT a char literal; a real char literal `'a'` IS $S ─────────────────
    const auto life = norm( "'a str" );                 // lifetime + type: ' punct, then two identifiers
    const auto clit = norm( "'a'" );                    // genuine char literal
    check( life.first == "' $I $I" && life.second == 3, "F2-a Rust lifetime 'a str -> ' $I $I (not $S)" );
    check( clit.first == "$S" && clit.second == 1,      "F2-a char literal 'a' -> $S" );
    check( life.first != clit.first,                    "MUT lifetime stream != char-literal stream" );

    // ── F2-b — C++14 digit separators collapse into ONE number token ─────────────────────────────────────
    check( norm( "1'000'000" ).first == "$N" && norm( "1'000'000" ).second == 1, "F2-b 1'000'000 -> single $N" );
    check( norm( "0xFF'FF'FF" ).first == "$N",                                    "F2-b hex 0xFF'FF'FF -> single $N" );
    // a separator-bearing number followed by real code keeps the code as its own tokens (no swallow).
    check( norm( "x = 1'000 + y" ).first == "$I = $N + $I",                       "F2-b 1'000 does not swallow trailing code" );

    // ── F2-c — real char literals still normalize to $S (fix must not over-correct) ──────────────────────
    check( norm( "'x'" ).first     == "$S", "F2-c 'x'  -> $S" );
    check( norm( "'\\n'" ).first   == "$S", "F2-c '\\n' -> $S" );
    check( norm( "'\\\\'" ).first  == "$S", "F2-c '\\\\' -> $S" );
    check( norm( "'\\0'" ).first   == "$S", "F2-c '\\0' -> $S" );
    check( norm( "'\\x41'" ).first == "$S", "F2-c '\\x41' -> $S" );
    // a pair of identical char-literal bodies must produce identical streams (Type-2 still fires downstream).
    check( norm( "if( c == 'a' ) x = '\\n';" ).first == norm( "if( c == 'a' ) x = '\\n';" ).first,
           "F2-c identical char-literal bodies normalize identically" );

    // ── F2-d — ' immediately after an identifier/digit byte is punctuation, never a literal opener ────────
    check( norm( "a'b'" ).first == "$I ' $I '", "F2-d a'b' -> ' after identifier is punctuation" );

    // ── F2-e — the core repro: two bodies differing ONLY after an unpaired lifetime ' must NOT collapse ───
    // Under the bug both bodies' differing tails were swallowed into one $S from the first ' onward, so the
    // streams were identical (a false exact clone). With the fix the label ' is punctuation and the tails
    // survive, so the streams differ.
    const std::string bodyA = "'outer: for w in it { acc += one; if acc > big { break 'outer; } }";
    const std::string bodyB = "'outer: for w in it { acc -= two; if acc < lil { break 'outer; } }";
    check( norm( bodyA ).first != norm( bodyB ).first, "F2-e differing post-lifetime bodies normalize DIFFERENTLY" );
    check( norm( bodyA ).second > 10 && norm( bodyB ).second > 10, "F2-e neither body collapsed to a stub token count" );

    // ── F2-f — `#` line comments dropped for hash-comment languages; kept as punctuation otherwise ───────
    // A contraction in the comment (`don't`) is exactly what used to open a runaway char literal.
    const std::string pyBody = "x = 1  # don't touch this\ny = 2";
    check( norm( pyBody, /*stripHash=*/true ).first == "$I = $N $I = $N", "F2-f Python `# don't ...` comment dropped when stripHash" );
    check( norm( pyBody, /*stripHash=*/false ).first != norm( pyBody, true ).first, "F2-f `#` kept (as punctuation) when !stripHash" );
    // two DIFFERENT Python bodies that share a contraction comment must NOT normalize identically (fix).
    const std::string py1 = "for it in xs:\n    # don't skip\n    a.append( it * 2 )\n    b = 3";
    const std::string py2 = "for it in xs:\n    # don't skip\n    a.append( it + 9 )\n    b = 7";
    check( norm( py1, true ).first != norm( py2, true ).first, "F2-f differing Python bodies w/ contraction comments differ" );

    // ── F2 parity — normalizeTokens (the Type-3 lexer) matches normalizeSpan's stream on the same inputs ─
    check( toks( "1'000'000" ) == "$N",           "parity normalizeTokens 1'000'000 -> $N" );
    check( toks( "'a str" )    == "' $I $I",       "parity normalizeTokens lifetime -> ' $I $I" );
    check( toks( "'x'" )       == "$S",            "parity normalizeTokens 'x' -> $S" );
    check( toks( pyBody, true ) == "$I = $N $I = $N", "parity normalizeTokens Python comment dropped" );

    // ── P3 — cloneIsKeyword membership (hash set) still correct ──────────────────────────────────────────
    check(  cloneIsKeyword( "if" ) && cloneIsKeyword( "return" ) && cloneIsKeyword( "impl" ) && cloneIsKeyword( "async" ),
            "P3 known keywords resolve true" );
    check( !cloneIsKeyword( "acc" ) && !cloneIsKeyword( "" ) && !cloneIsKeyword( "iff" ),
            "P3 non-keywords resolve false" );

    if( g_fail ) { std::fprintf( stderr, "clonelex_harness: FAIL\n" ); return 1; }
    std::printf( "clonelex_harness: ALL PASS\n" );
    return 0;
}
