#pragma once

// regexguard.h — THE owner of user-authored regular expressions: the structural screen, the compile, and the
// match. Every pattern a user writes — `--regex`, `--graph-query file()`, an `--arch` path-rule, a `#match?` /
// `#not-match?` predicate in `--match` or `--lint-rules` — is compiled by compileGuardedRegex and matched
// through a GuardedRegex. No other file in src/ spells std::regex (test/regexguardcheck.sh arm (c)).
//
// WHY A SEAM. The screen used to live in src/search.h beside `--regex`, the one entry point that called it. The
// other three handed a user's pattern straight to the standard library, and a regex_error thrown there had no
// handler:
//
//     ripwire <dir> --graph-query='file(all,"(a+)+z")'          rc=134  uncaught std::regex_error (libc++)
//     ripwire <dir> --arch=rules   (deny path zz/.* -> (a+)+z)   rc=134  the same abort
//     ripwire <dir> --match='… (#match? @id "(a+)+z")'           rc=0    the throw was swallowed, the row KEPT
//
// Each copy of "compile a user's regex" had grown its own policy — screened or not, catch the compile or not,
// catch the match or not, keep or drop on a throw — and the differences were the bugs. One owner gives every
// entry point the same three verdicts: a named refusal before any engine sees the pattern, a named refusal
// when the engine gives up mid-match, or an answer.
//
// WHAT A CALL SITE GETS
//   compileGuardedRegex( pattern, syntax ) → { regex, refusal, isScreened }. `refusal` is the SAME text
//       `--regex` has always printed after "refused, nothing was scanned:" — the screen's message, or the
//       engine's own diagnostic. `isScreened` says which, for a caller whose malformed-pattern wording predates
//       the screen and is pinned (--arch). The screen runs FIRST, so its verdict is identical on every standard
//       library: a pattern one engine abandons and the other backtracks on forever gets one answer, not two.
//   GuardedRegex::search / forEachMatch → RegexVerdict { Miss, Hit, Exhausted, Skipped }. Exhausted is a
//       regex_error thrown DURING the match (libc++'s error_complexity / error_stack): the screen is a static
//       approximation, and what it still cannot see is a CRAFTED SUBJECT under a pattern it admits — since
//       M2-c the overlapping alternation it used to name here, (a|a)+z, is refused by the screen instead. It
//       is never Miss. METHODOLOGY §9: an
//       abandoned match is "unknown", and a caller that folds it into "no hit" reports a zero it did not
//       measure. Every entry point refuses on it by name, quoting kRegexAbandonedReason. Skipped is a subject
//       NEVER HANDED to the engine because it exceeds this thread's measured-safe bound (maxEngineSubjectBytes)
//       — search()/search(subject,captures) take an optional stackBytes (default SIZE_MAX, i.e. unbounded, so
//       every caller that does not pass one is untouched); a caller off the grep line-loop (forEachLineMatch
//       already bounds itself) passes one explicitly. Skipped is exactly as "unknown" as Exhausted and every
//       entry point refuses on it the same way, quoting kRegexOversizeReason.
//
// THE ONE EXCEPTION BOUNDARY. std::regex reports through exceptions — regex_error from the parser and from the
// matcher, bad_alloc from either — and this codebase avoids exception handling (CONTRIBUTING §3: a recoverable
// error is a value, returned; RAII, not catch blocks, owns cleanup). So this header is the only place in src/
// that catches either, and it catches exactly those two, by type, and converts them to VALUES: a refusal
// string, or RegexVerdict::Exhausted. No catch(...) — a throw of any other type is not something a regex
// engine raises, and swallowing it would hide a bug rather than disclose a limit. Every public entry point is
// noexcept, so nothing above the seam ever sees an exception from the engine, and a call site holds no try.
// (Building a refusal string can itself allocate; under noexcept an allocation failure there terminates,
// which is the house rule that throws belong to the operator new seam alone.) Nothing here owns a resource
// a handler would have to release: the compiled regex is a value member, destroyed by its owner.
//
// COST. The screen is one linear pass over the pattern, once per compile, and a compile happens exactly where
// one happened before (once per query, per rule, per grep worker — never per file or per hit). The try around a
// match is table-based: nothing runs on the non-throwing path. The fault switch below is `constexpr false`
// under NDEBUG, so the branch and the getenv are deleted from a release build. Measured in the lane that made
// this seam: byte-identical output on every touched verb, release __text size in the CHANGELOG entry.
//
// THE ALLOWLIST, and why it is empty. src/skillscan.h was a row until its patterns moved behind this header: a skill
// file is untrusted input, so an abandoned match there must fail closed rather than abort wrap's noexcept scan.
// src/redact.h was the last row — a constant rule table — until libstdc++'s per-state recursion made it the same Linux
// crash on a long token run in a default run's emitted bodies; its rules are now matched structurally, with each
// regex kept as the specification arm (o) diffs against. A new constant table needs a reason at least that strong; a
// pattern a user can type never gets a row.

#include "infra/emit.h"      // rw::faultSwitchOn — the one reader every non-NDEBUG fault switch goes through
#include "infra/stackthreads.h"   // kCallerStackBytesFloorLibstdcxx — the caller floor's engine budget is asserted below
#include "infra/strkern.h"   // findByte / find3 / findByteset / lowerFoldedEquals — the literal paths' byte kernels

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <locale>     // std::locale::classic — icase folds through the regex's locale, and only the classic one is ASCII-only
#include <new>        // std::bad_alloc — the one other exception type the engine raises, caught here by type
#include <optional>
#include <regex>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// L5 (Linux runtime probe) — the ONE place the two standard libraries disagree about what a valid pattern
// IS, closed here so the binary answers the same question on both.
//
// ECMAScript's IdentityEscape forbids `\<letter>` for any letter that is not a recognised escape, and libc++
// enforces it: `--regex='\Q\E'` is refused on macOS. libstdc++ does not — on Ubuntu the same pattern
// COMPILES, with `\Q` silently meaning the literal letter Q. That is the worse half of the split: the
// lenient side does not error, it answers a DIFFERENT question and hands the result back as a measurement.
//
// So the pattern is screened before either engine sees it, against the escapes libc++ actually accepts
// (measured with a probe, not inferred from the grammar): `\b \B \d \D \s \S \w \W \f \n \r \t \v` alone,
// plus `\c \x \u`, whose TAILS the engine still validates. Everything else after a backslash — digits
// (back-references), `$`, `_`, punctuation, any non-ASCII byte — is left entirely to the engine, which
// agrees about all of it. So this rejects EXACTLY the set libc++ already rejected and nothing more: no
// pattern that searches on macOS today stops searching, and Linux stops silently misreading the Perl-isms.
inline constexpr std::string_view kPortableRegexLetterEscapes = "bBdDsSwWfnrtv";   // valid on their own
inline constexpr std::string_view kPortableRegexPrefixEscapes = "cxu";             // valid with a tail the engine checks

inline std::optional<std::string> nonPortableRegexEscape( const std::string& pat )
{
    for( std::size_t i = 0; i + 1 < pat.size(); ++i )
    {
        if( pat[i] != '\\' )
        {
            continue;
        }

        const char escaped = pat[ i + 1 ];
        ++i;                                                                          // consume it: `\\Q` is an escaped backslash then a plain Q, not an escaped Q
        const bool isAsciiLetter =    ( escaped >= 'a' && escaped <= 'z' )
                                   || ( escaped >= 'A' && escaped <= 'Z' );
        if( !isAsciiLetter )
        {
            continue;
        }
        if( kPortableRegexLetterEscapes.find( escaped ) != std::string_view::npos )
        {
            continue;
        }
        if( kPortableRegexPrefixEscapes.find( escaped ) != std::string_view::npos )
        {
            continue;
        }

        return   std::string( "unsupported escape sequence '\\" ) + escaped + "' — the portable ECMAScript escapes are "
                 "\\b \\B \\d \\D \\s \\S \\w \\W \\f \\n \\r \\t \\v \\cX \\xHH \\uHHHH (some C++ standard libraries accept '\\"
               + escaped + "' and silently read it as the literal '" + escaped + "', so it is refused rather than answered differently per platform)";
    }
    return std::nullopt;
}

// M2 (Linux runtime probe) — the SECOND thing the two standard libraries disagree about, and the worse
// one. `--regex='(a+)+b'` over a long run of 'a' with no 'b' is the textbook catastrophic-backtracking
// shape: every way of splitting the run between the inner and the outer repetition is a distinct path,
// so a backtracking engine explores O(2^n) of them before it can report no-match.
//
// Apple libc++ has a complexity budget and gives up in well under a second with
// regex_error(error_complexity), which grepScanText's catch turned into a skipped file — the original
// A4-F10 "degrade, don't die" contract, and the only behaviour this repo had ever observed (a skipped file
// is a silent floor; GuardedRegex below now turns it into a refusal by name). libstdc++ has
// NO such budget: it never throws, so that catch is never reached and the process simply backtracks. The
// first real Linux run (Ubuntu 24.04, clang 18 + libstdc++) was still CPU-bound at 560 s on the very
// fixture the gate uses, i.e. on Linux a pathological --regex does not degrade — it hangs the tool.
//
// So the pattern is screened HERE, structurally, before either engine is handed it, for the same reason
// and in the same shape as the L5 escape screen above: the verdict must be a pure function of the pattern
// text, not of whose backtracker is linked in and not of what happens to be in the corpus. Refusal is the
// right outcome rather than a silent skip — a skipped file reads as a measurement, an exit-1 refusal that
// names the construct cannot.
//
// M2-b (Linux RE-smoke) — the first cut of this screen refused only an unbounded quantifier over a group
// that repeated WITHOUT bound inside it, and let (a?)+ and (a{1,3})+ through as "bounded inner, cannot
// blow up". That was libc++ behaviour written down as a law. On Ubuntu 24.04 / clang 18 / libstdc++ both
// of those patterns HANG — the re-smoke killed them on the harness's wall-clock cap, on the same fixture
// and in the same way as (a+)+b, and they had been shipping as this gate's "must still scan" controls.
// BOUNDED IS NOT UNAMBIGUOUS: '(a?)+' splits a run of 'a' in as many ways as '(a+)+' does, because the
// inner may also match EMPTY, and '(a{1,3})+' because the inner's width varies. So the screen is widened
// rather than the verdict split per platform.
//
// WHAT IS CAUGHT: an unbounded quantifier ('*', '+', '{n,}') applied to a group that contains ANY
// quantifier anywhere inside it, at any nesting depth — bounded ones included. (X+)+, (X*)*, (X+)*,
// (X{n,})+, ((X+))+, ((X)+)+, (X+|Y)+ as before, and now (X?)+, (X{m,n})+, ((X)?)+ and (X{n})+ too.
// Exact '{n}' is in ON PURPOSE: a fixed-count inner is only unambiguous when what it repeats is itself
// fixed-width, and '((ab|c){2})+d' is a real bomb that reading the quantifier alone cannot tell apart from
// '(a{3})+b'. A screen that must return ONE verdict on two different backtrackers cannot make that call.
//
// WHAT IS DELIBERATELY NOT CAUGHT, so the guard does not quietly eat working patterns: a group with no
// quantifier inside passes however it is quantified, so (abc)+ and (a)+b pass; a BOUNDED outer
// quantifier passes whatever the group contains, which is what keeps the workaround this very message
// suggests — '(\s*\w+){1,20}' — legal; an UNQUANTIFIED group passes whatever it contains, so (a+)b, (a?)b
// and (a+)(b)+ pass; '+' inside a character class or behind a backslash is a literal, so [a+]+ and (\+)+
// pass; and the '?' that opens '(?:', '(?=' or '(?!' is a group MODIFIER, not a quantifier, so (?:abc)+
// passes while (?:a+)+b is still refused.
//
// THE SECOND ARM — overlapping alternation, closed 2026-10-12 (M2-c), widened 2026-10-15 (M2-e). A group whose
// branches carried no quantifier at all used to pass however it was quantified, which made `(a|a)+b` a real bomb
// the screen could not see; that was the audit's live PoC `^(a|aa)+b$`, and this file used to name it as the known
// GAP. The screen cannot read semantics, so it now refuses a group's own top-level '|' under an unbounded outer
// UNLESS it can prove the branches disjoint, and the proofs run in two strengths: M2-c's is the cheap whole-
// footprint one — every branch consumes exactly ONE character, and all those characters must be pairwise
// disjoint, which keeps `(a|b)+` and `(\d|[a-z])+` passing and refuses `(a|a)+b`, `^(a|aa)+b$`, `(x|xy)+c$` and
// `(\w|\d)+$`; M2-e proves one level weaker so it reads branches M2-c cannot: a branch that is an UNQUANTIFIED
// sequence of width-one atoms has a fixed width and matches deterministically once started, so the only question
// left is which branch starts a position, and the branch's first character answers it in one. Pairwise-disjoint
// first-character sets across every branch settle that — `'([^"\]|\\.)*'`, `(\r\n|\n)+`, `(cat|dog)+` and
// `(foo|bar)+` are admitted — while the shapes M2-c was built for stay refused: `(a|aa)+` and
// `(get|getResponse)+` repeat branches whose FIRST character is the same, so the split ambiguity the first
// character cannot break is exactly what they have. What stays outside BOTH proofs is refused as before named:
// a branch with a quantifier of its own (its width varies, the ambiguity is back), an anchor or other zero-width
// head (no first character to decide with), a nested group (its choice structure is not modelled), an empty
// branch (an empty-loop hazard). The price of M2-e is a smaller known false-positive class than M2-c's, still
// stated rather than discovered: a NON-DETERMINISTIC alternation whose branches share a first character is
// indistinguishable, without matching it, from one that overlaps another, and a screen that must return ONE
// verdict cannot tell them apart. Refusal is a safe failure, a hang is not — and the refusal says what it
// actually knows ("cannot PROVE are disjoint"), NOT that the branches overlap, because for disjoint branches it
// is the PROOF that failed, not the branches; the only workaround it names is bounding the OUTER quantifier,
// which works for the whole class (PM-1, 2026-10-12). Every one of these cases is an arm of
// test/regexbombcheck.sh.
//
// M2-d (round 6, the PR #397 review's PAREN BYPASS). The alternation arm judged a group only when an
// unbounded quantifier sat ON it — so an alternation one group deeper sailed past untouched:
// '((a|aa))+b$' closes its inner group under NO quantifier, only hasQuantifierInside ever reached the
// parent frame, and the outer '+' repeated an alternation the screen cannot prove disjoint without ever
// judging it. The arm was checking the right fact in the wrong place. The screen now carries that verdict
// up the frame stack exactly the way hasQuantifierInside travels: a group whose own top-level '|' is not
// proven disjoint sets hasUnprovenAlternationInside on its parent when it closes (whatever quantified IT),
// and a group that closes under an unbounded quantifier with that flag set is refused by the SAME
// alternation sentence. '((a|aa))+b$' and '(?:(?:a|aa))+b$' are refused; every alternation the screen CAN
// prove disjoint — (a|b)+, and one nested inside a quantified group — still scans.
//
// Scope: EVERY user-authored pattern, through compileGuardedRegex below — --regex, --graph-query file(), the
// --arch path-rules and the #match?/#not-match? predicates of --match and --lint-rules. This paragraph used to
// scope the screen to --regex alone, on the reasoning that --arch rules "come from a committed rules file, not
// from the command line"; that exemption is how `file(all,"(a+)+z")` and `deny path zz/.* -> (a+)+z` reached
// the engine unscreened and aborted the process (rc 134 on libc++). A rules file is user-authored text exactly
// as an argument is.
struct RegexQuantifier { bool isPresent; bool isUnbounded; std::size_t lengthCount; };

// reads the quantifier at `at`, if there is one. '?' and '{n,m}' are quantifiers but BOUNDED; anything
// that is not a well-formed '{' interval is not a quantifier at all, just a literal brace.
inline RegexQuantifier regexQuantifierAt( const std::string& pat, std::size_t at )
{
    if( at >= pat.size() )
    {
        return { false, false, 0 };
    }
    if( pat[at] == '*' || pat[at] == '+' )
    {
        return { true, true, 1 };
    }
    if( pat[at] == '?' )
    {
        return { true, false, 1 };
    }
    if( pat[at] != '{' )
    {
        return { false, false, 0 };
    }

    std::size_t cursor         = at + 1;
    std::size_t lowerDigitCount = 0;
    while( cursor < pat.size() && pat[ cursor ] >= '0' && pat[ cursor ] <= '9' ) { ++cursor; ++lowerDigitCount; }
    if( lowerDigitCount == 0 )
    {
        return { false, false, 0 };
    }
    if( cursor < pat.size() && pat[cursor] == '}' )
    {
        return { true, false, ( cursor + 1 ) - at }; // {n} — exact, bounded
    }
    if( cursor >= pat.size() || pat[cursor] != ',' )
    {
        return { false, false, 0 };
    }

    ++cursor;
    std::size_t upperDigitCount = 0;
    while( cursor < pat.size() && pat[ cursor ] >= '0' && pat[ cursor ] <= '9' ) { ++cursor; ++upperDigitCount; }
    if( cursor >= pat.size() || pat[cursor] != '}' )
    {
        return { false, false, 0 };
    }

    return { true, upperDigitCount == 0, ( cursor + 1 ) - at };                                           // {n,} unbounded, {n,m} bounded
}

// '(?:' / '(?=' / '(?!' — a '?' immediately after '(' opens a NON-CAPTURING or lookaround group. It is a
// group MODIFIER, not a quantifier, and reading it as one (which M2-b's widened flag otherwise would)
// refuses every '(?:abc)+' ever written. Returns how many characters after the '(' the modifier occupies,
// so the caller's `i += length` lands the scan on the group's BODY.
//
// M2-c fixes two things here that the quantifier scan alone could not see, and neither changes its verdict.
// (1) The count is now the WHOLE modifier: '(?:' is 2, not 1, because the body of '(?:a|b)+' starts at the
// 'a' and not at the ':' — the old count left the ':' to be re-scanned as an ordinary character, which was
// harmless until the alternation arm started reading a group's body from this offset, at which point every
// branch of a non-capturing group began with a stray ':' and a disjoint alternation was refused.
// (2) The two '<' forms are now handled: '(?<name>' is a NAMED group whose name is part of the modifier,
// and '(?<=' / '(?<!' are lookbehind. Both would otherwise be read as body text.
inline std::size_t regexGroupModifierLength( const std::string& pat, std::size_t openAt )
{
    if( openAt + 1 >= pat.size() || pat[ openAt + 1 ] != '?' )
    {
        return 0;   // '(' … — an ordinary capturing group
    }
    if( openAt + 2 >= pat.size() )
    {
        return 1;   // a bare '(?' — malformed, and the compile probe below owns that error
    }
    if( pat[ openAt + 2 ] != '<' )
    {
        return 2;   // '(?:' / '(?=' / '(?!'
    }
    if( openAt + 3 < pat.size() && ( pat[ openAt + 3 ] == '=' || pat[ openAt + 3 ] == '!' ) )
    {
        return 3;   // '(?<=' / '(?<!' — lookbehind, no name
    }
    for( std::size_t cursor = openAt + 3; cursor < pat.size(); ++cursor )
    {
        if( pat[ cursor ] == '>' )
        {
            return cursor - openAt;   // '(?<name>' — everything through the '>' is the modifier
        }
    }
    return 2;       // an unterminated name: the compile probe below owns that error
}

// The two refusal sentences below share their opening — the construct, and the quantifier applied to it. Spelled
// out in both, that opening was twenty-four identical normalized tokens, which --quality-delta reports as a
// duplication pair; it lives here once. The caller supplies the clause naming WHAT repeats, and the concatenation
// is the same bytes either way (regexguardcheck.sh pins the wording at every entry point).
inline std::string catastrophicRegexPrologue( char outerQuant )
{
    return std::string( "catastrophic backtracking: the unbounded quantifier '" ) + outerQuant + "' is applied to ";
}

// The one refusal this screen emits, kept out of the scan loop so the loop reads as the small state
// machine it is. `outerQuant` is the quantifier character that was applied to the offending group.
inline std::string catastrophicRegexMessage( char outerQuant )
{
    return   catastrophicRegexPrologue( outerQuant ) + "a group whose contents "
             "already repeat (the (X+)+ / (X*)* / (X+)* / (X{n,})+ family, and equally the bounded-inner (X?)+ / (X{m,n})+ / (X{n})+ one). "
             "Every way of splitting the input between the inner and the outer repetition is a separate path, so matching a non-matching "
             "line costs time exponential in its length; a BOUNDED inner is no defence, because it is ambiguity and not unboundedness that "
             "multiplies the paths. std::regex has no backtracking budget you can set, and the standard libraries do not agree about it — "
             "libc++ abandons the match in under a second, libstdc++ never gives up at all (measured on Ubuntu 24.04 / clang 18 / libstdc++: "
             "'(a+)+b' still running after 560 s, and '(a?)+b' and '(a{1,3})+b' both still running when the harness killed them) — so this "
             "is refused rather than answered differently per platform. Workaround: collapse the two repetitions into one, since the outer "
             "adds no string the inner does not already match ('(a+)+' is the language of 'a+', '(a?)+' of 'a*', '(a{1,3})+' of 'a+'), or "
             "make the OUTER bounded with an explicit interval ('(\\s*\\w+){1,20}')";
}

// ── the ALTERNATION arm's character sets (M2-c, 2026-10-12) ─────────────────────────────────────────────
//
// To refuse `(a|a)+` the screen has to see that two branches can match the SAME text, and it cannot read
// semantics. So it compares CHARACTER SETS, and only for a branch it can prove consumes exactly one
// character. The sets are dense over ASCII 0..127 with one flag for "reaches past ASCII", which is what
// makes the complements ('\D', '\W', '\S', '[^…]') answerable without a Unicode table: a byte outside ASCII
// is matched by every complement and by '.', and by no shorthand and no literal. A branch the parser will
// not commit to gets NO set, and the caller refuses — the conservative direction, and the reason '[]',
// '[[:alpha:]]', '\p{L}', '\b' and a backreference are refusals rather than guesses.
inline constexpr unsigned kRegexCharSetAscii = 128;   // dense range: 0..63 in asciiLow, 64..127 in asciiHigh

struct RegexCharSet
{
    std::uint64_t asciiLow        = 0;
    std::uint64_t asciiHigh       = 0;
    bool          matchesNonAscii = false;

    void add( unsigned char c ) { ( c < 64 ? asciiLow : asciiHigh ) |= std::uint64_t( 1 ) << ( c & 63 ); }
    void remove( unsigned char c ) { ( c < 64 ? asciiLow : asciiHigh ) &= ~( std::uint64_t( 1 ) << ( c & 63 ) ); }
    bool has( unsigned char c ) const { return ( ( c < 64 ? asciiLow : asciiHigh ) >> ( c & 63 ) ) & 1; }
};

inline RegexCharSet regexCharSetOfDigit()
{
    RegexCharSet set;
    for( unsigned char c = '0'; c <= '9'; ++c ) { set.add( c ); }
    return set;
}

inline RegexCharSet regexCharSetOfWord()
{
    RegexCharSet set = regexCharSetOfDigit();
    for( unsigned char c = 'A'; c <= 'Z'; ++c ) { set.add( c ); }
    for( unsigned char c = 'a'; c <= 'z'; ++c ) { set.add( c ); }
    set.add( '_' );
    return set;
}

inline RegexCharSet regexCharSetOfSpace()
{
    RegexCharSet        set;
    const unsigned char bytes[] = { ' ', '\t', '\n', '\r', '\f', '\v' };
    for( unsigned char c : bytes ) { set.add( c ); }
    return set;
}

inline RegexCharSet regexCharSetOfAny()   // '.' — ECMAScript's dot without dotAll: every byte but a line terminator
{
    RegexCharSet set;
    set.asciiLow        = ~std::uint64_t( 0 );
    set.asciiHigh       = ~std::uint64_t( 0 );
    set.matchesNonAscii = true;
    set.remove( '\n' );
    set.remove( '\r' );
    return set;
}

inline RegexCharSet regexCharSetComplement( const RegexCharSet& base )
{
    RegexCharSet set;
    set.asciiLow        = ~base.asciiLow;
    set.asciiHigh       = ~base.asciiHigh;
    set.matchesNonAscii = true;   // the complement of an ASCII-only set always reaches past ASCII
    return set;
}

inline bool regexCharSetsIntersect( const RegexCharSet& a, const RegexCharSet& b )
{
    if( ( a.asciiLow & b.asciiLow ) != 0 || ( a.asciiHigh & b.asciiHigh ) != 0 )
    {
        return true;
    }
    return a.matchesNonAscii && b.matchesNonAscii;
}

// '\d' '\D' '\w' '\W' '\s' '\S' — the one-character classes ECMAScript spells with a backslash.
inline bool regexCharSetOfShorthand( char escaped, RegexCharSet& out )
{
    switch( escaped )
    {
        case 'd': out = regexCharSetOfDigit();                           return true;
        case 'D': out = regexCharSetComplement( regexCharSetOfDigit() );  return true;
        case 'w': out = regexCharSetOfWord();                            return true;
        case 'W': out = regexCharSetComplement( regexCharSetOfWord() );   return true;
        case 's': out = regexCharSetOfSpace();                           return true;
        case 'S': out = regexCharSetComplement( regexCharSetOfSpace() );  return true;
        default:  return false;
    }
}

// the set of ONE escaped character, when it consumes exactly one. false = the parser will not commit: a
// zero-width assertion ('\b', '\B'), a backreference ('\1'…'\9', '\k'), a Unicode property, or a
// decodable-but-undecoded '\x' / '\u' / '\c' escape. Every one of those is a REFUSAL at the call site.
inline bool regexCharSetOfEscape( char escaped, RegexCharSet& out )
{
    if( regexCharSetOfShorthand( escaped, out ) )
    {
        return true;
    }
    switch( escaped )
    {
        case 'b': case 'B': case 'k': case 'p': case 'P': case 'x': case 'u': case 'c':
            return false;
        default:
            break;
    }
    if( escaped >= '1' && escaped <= '9' )
    {
        return false;
    }
    out = {};
    switch( escaped )
    {
        case 'n': out.add( '\n' ); break;
        case 'r': out.add( '\r' ); break;
        case 't': out.add( '\t' ); break;
        case 'f': out.add( '\f' ); break;
        case 'v': out.add( '\v' ); break;
        case '0': out.add( '\0' ); break;
        default:  out.add( static_cast<unsigned char>( escaped ) ); break;   // '\.', '\+', '\\', '\/' … a literal
    }
    return true;
}

// true when the set is EXACTLY one ASCII character — what a range endpoint must be. '\d' is ten characters
// and '.' is a hundred and twenty-six, so neither may be an endpoint.
inline bool regexCharSetAsOneAsciiByte( const RegexCharSet& set, unsigned char& byte )
{
    if( set.matchesNonAscii )
    {
        return false;
    }
    int found = -1;
    for( unsigned char c = 0; c < kRegexCharSetAscii; ++c )
    {
        if( set.has( c ) )
        {
            if( found >= 0 )
            {
                return false;
            }
            found = c;
        }
    }
    if( found < 0 )
    {
        return false;
    }
    byte = static_cast<unsigned char>( found );
    return true;
}

// the set of ONE character class, '[' … ']'. `next` is left just past the closing ']'. false = the parser
// will not commit: an empty class, an unterminated one, a nested '[', or a range whose endpoint is not a
// single character ('[a-\d]', '[\w-z]') — all refusals rather than guesses.
inline bool regexCharSetOfClass( const std::string& pat, std::size_t openAt, std::size_t end, RegexCharSet& out, std::size_t& next )
{
    out = {};
    std::size_t cursor  = openAt + 1;
    const bool  negated = cursor < end && pat[ cursor ] == '^';
    if( negated )
    {
        ++cursor;
    }

    bool anyMember = false;
    while( cursor < end && pat[ cursor ] != ']' )
    {
        RegexCharSet member;
        std::size_t  memberEnd = cursor;
        if( pat[ cursor ] == '\\' )
        {
            if( cursor + 2 > end || !regexCharSetOfEscape( pat[ cursor + 1 ], member ) )
            {
                return false;
            }
            memberEnd = cursor + 2;
        }
        else
        {
            if( pat[ cursor ] == '[' )
            {
                return false;   // a nested '[' is not a member of this screen's class model
            }
            member = {};
            member.add( static_cast<unsigned char>( pat[ cursor ] ) );
            memberEnd = cursor + 1;
        }

        // a RANGE is '-' between two single characters; anything else is refused
        if( memberEnd < end && pat[ memberEnd ] == '-' && memberEnd + 1 < end && pat[ memberEnd + 1 ] != ']' )
        {
            RegexCharSet upper;
            std::size_t  upperEnd = memberEnd + 1;
            if( pat[ upperEnd ] == '\\' )
            {
                if( upperEnd + 2 > end || !regexCharSetOfEscape( pat[ upperEnd + 1 ], upper ) )
                {
                    return false;
                }
                upperEnd += 2;
            }
            else
            {
                upper = {};
                upper.add( static_cast<unsigned char>( pat[ upperEnd ] ) );
                ++upperEnd;
            }
            unsigned char lowerByte = 0, upperByte = 0;
            if( !regexCharSetAsOneAsciiByte( member, lowerByte ) || !regexCharSetAsOneAsciiByte( upper, upperByte ) || lowerByte > upperByte )
            {
                return false;
            }
            for( unsigned char c = lowerByte; c <= upperByte; ++c )
            {
                out.add( c );
            }
            cursor    = upperEnd;
            anyMember = true;
            continue;
        }

        for( unsigned char c = 0; c < kRegexCharSetAscii; ++c )
        {
            if( member.has( c ) )
            {
                out.add( c );
            }
        }
        out.matchesNonAscii = out.matchesNonAscii || member.matchesNonAscii;
        cursor              = memberEnd;
        anyMember           = true;
    }

    if( cursor >= end || pat[ cursor ] != ']' || !anyMember )
    {
        return false;
    }
    next = cursor + 1;
    if( negated )
    {
        out = regexCharSetComplement( out );
    }
    return true;
}

// The character set of a branch that consumes EXACTLY ONE character, or false when the branch is anything
// else — two characters, a quantifier, an anchor, an empty branch, a backreference. false is not an error:
// it is the caller's signal that disjointness cannot be proven, so the caller refuses.
inline bool regexCharSetOfSingleCharBranch( const std::string& pat, std::size_t begin, std::size_t end, RegexCharSet& out )
{
    if( begin >= end )
    {
        return false;   // an empty branch matches the EMPTY STRING — exactly the ambiguity this arm exists for
    }
    const char c = pat[ begin ];
    if( c == '\\' )
    {
        return begin + 2 == end && regexCharSetOfEscape( pat[ begin + 1 ], out );
    }
    if( c == '[' )
    {
        std::size_t next = begin;
        return regexCharSetOfClass( pat, begin, end, out, next ) && next == end;
    }
    if( c == '.' )
    {
        if( begin + 1 != end )
        {
            return false;
        }
        out = regexCharSetOfAny();
        return true;
    }
    // a one-character atom cannot be an anchor, a group delimiter or a quantifier
    if( c == '^' || c == '$' || c == '|' || c == '(' || c == ')' || c == '*' || c == '+' || c == '?' || c == '{' || c == '}' || c == ']' )
    {
        return false;
    }
    if( begin + 1 != end )
    {
        return false;
    }
    out = {};
    out.add( static_cast<unsigned char>( c ) );
    return true;
}

// ── M2-e (round 6, the PR #397 review): the FIRST-CHARACTER arm — prove disjointness one element deeper ──────
//
// M2-c could only prove a branch's WHOLE footprint, so every multi-character branch was refused wholesale and
// the false-positive class was real code: the quoted-string matcher "([^"\]|\\.)*", a CRLF walker (\r\n|\n)+,
// keyword pairs with no shared first character ((cat|dog)+, (foo|bar)+). A branch that is an UNQUANTIFIED
// sequence of width-one atoms is decidable one level weaker. Its width is fixed, so once started it matches
// deterministically — there is one path through it, no choices for a backtracker to enumerate — and the only
// remaining ambiguity is WHICH branch starts a position, decided by the branch's first character alone. When
// every branch parses as such a sequence and the branches' first-character sets are pairwise disjoint, at most
// one branch is viable at any position and the repetition cannot multiply: proven disjoint, admit.
//
// Everything outside that model stays unproven, refused with the same sentence as before, and each residue is a
// hazard this weaker proof cannot cover: a branch with a quantifier of its own varies in width, so the input can
// be split between the branches and the repetition ambiguously; an anchor or other zero-width head has no first
// character to decide with; a nested group's choice structure is not modelled; an empty branch matches the empty
// string, an empty-loop hazard in its own right. (a|aa)+ and (get|getResponse)+ stay refused because their
// branches' first-character sets are the SAME set — disjoint first characters are exactly what they lack.
inline bool regexFirstCharSetOfQuantifierFreeBranch( const std::string& pat, std::size_t begin, std::size_t end, RegexCharSet& first )
{
    if( begin >= end )
    {
        return false;   // an empty branch matches the EMPTY STRING — the empty-loop hazard stays unproven
    }
    bool firstResolved = false;
    for( std::size_t i = begin; i < end; )
    {
        const char c = pat[ i ];
        if( c == '\\' )
        {
            RegexCharSet member;
            if( i + 2 > end || !regexCharSetOfEscape( pat[ i + 1 ], member ) )
            {
                return false;   // trailing backslash, or an escape this screen will not commit to ('\b', '\1', '\x'…)
            }
            if( !firstResolved )
            {
                first         = member;
                firstResolved = true;
            }
            i += 2;
            continue;
        }
        if( c == '[' )
        {
            RegexCharSet member;
            std::size_t  next = i;
            if( !regexCharSetOfClass( pat, i, end, member, next ) )
            {
                return false;   // a class this model cannot read (nested '[', a bad range, unterminated)
            }
            if( !firstResolved )
            {
                first         = member;
                firstResolved = true;
            }
            i = next;
            continue;
        }
        // '.' is a plain width-one atom to this arm's width argument, but its first set is every byte but a
        // line terminator — which intersects anything — so a wildcard-headed branch must not pretend to a
        // smaller first set here or it would be admitted ambiguously.
        if( c == '.' )
        {
            if( !firstResolved )
            {
                first         = regexCharSetOfAny();
                firstResolved = true;
            }
            ++i;
            continue;
        }
        // A quantifier ends the question (the branch's width would vary), and so do parentheses (a nested
        // group's own choice structure is not modelled), anchors and the delimiters the single-char arm
        // refuses as atoms — nothing here gets a first character one branch at a time can disagree on.
        if( c == '*' || c == '+' || c == '?' || c == '{' || c == '(' || c == ')' || c == '^' || c == '$' || c == '}' || c == ']' )
        {
            return false;
        }
        if( !firstResolved )
        {
            first = {};
            first.add( static_cast<unsigned char>( c ) );
            firstResolved = true;
        }
        ++i;
    }
    return firstResolved;
}

// The alternation arm's refusal, in the same voice as catastrophicRegexMessage above: name the construct, say why
// the paths multiply, and leave the reader a workaround. Every gate that greps a refusal for 'backtrack' and for
// a workaround ('collapse' or 'bounded') reads this sentence too.
//
// PM-1 (2026-10-12, PM-directed). The wording used to ASSERT the branches "can match the same text". The refusal
// now fires only when BOTH proofs fail — M2-c's whole-footprint single-character proof and M2-e's
// first-character proof — so the branches are unmodelled (a quantifier, an anchor head, a nested group) or their
// first characters are provably the SAME; for that class the old claim can still be false, and the workaround it
// taught ("factor the branches so no two of them can match the same text") cannot be applied to branches that
// are ALREADY disjoint. A screen that refuses a shape it cannot read must say what it actually knows: it cannot
// PROVE the branches disjoint. The actionable workaround — bounding the OUTER quantifier — works for every
// pattern this class can hold, so it carries alone.
inline std::string catastrophicRegexAlternationMessage( char outerQuant )
{
    return   catastrophicRegexPrologue( outerQuant ) + "an alternation whose "
             "branches the structural screen cannot PROVE are disjoint. A branch carries no quantifier of its own, so the "
             "nested-repetition refusal cannot see this one, and the character-set proofs cover a branch only when it is an "
             "unquantified sequence of width-one atoms whose FIRST character differs from every other branch's: a branch with a "
             "quantifier, a zero-width head or a nested group — or one sharing its first character with another — leaves the "
             "input splittable between the branches and the outer repetition, every split a separate path, so matching a "
             "non-matching line costs time exponential in its length. Workaround: make the OUTER quantifier a small explicit bound "
             "('(X){1,5}' for whatever the group is, a ceiling every engine honours identically)";
}

// The group's own top-level branch spans, in order. ONE splitter for the two disjointness proofs (M2-c's
// whole-footprint sets and M2-e's first-character sets), so they cannot disagree about what a branch is.
inline void regexTopLevelBranchSpans( std::size_t bodyBegin, std::size_t closeAt, const std::vector<std::size_t>& pipes,
                                      std::vector<std::pair<std::size_t, std::size_t>>& out )
{
    out.clear();
    std::size_t begin = bodyBegin;
    for( std::size_t k = 0; k <= pipes.size(); ++k )
    {
        const std::size_t end = ( k < pipes.size() ) ? pipes[ k ] : closeAt;
        out.push_back( { begin, end } );
        begin = end + 1;
    }
}

// What the two disjointness proofs decided about a group's own top-level '|'. ONE selector, two strengths — a
// two-symbol clone (the shape --quality-delta gates on) is a negative outcome for proofs that must not be able
// to disagree about what a branch or an intersection is. The pairwise-intersection test each proof ends with is
// inlined here twice rather than raised to a helper on purpose: a standalone one-loop helper IS that test's own
// clone shape (it duplicate-matched src/mergescout.h's overlap loop the moment it existed, measured
// --quality-delta), and a helper shared across FILES would make the two proofs parse intersection through another
// file's seam.
//   DisjointWholeFootprint — M2-c: every branch consumes exactly ONE character and the characters are pairwise
//                           disjoint; the strongest wording, and every verdict it makes is byte-identical to
//                           round 5's.
//   DisjointFirstChar      — M2-e: M2-c cannot read the branches, but every branch is an unquantified sequence
//                           of width-one atoms and the branches' FIRST characters are pairwise disjoint, so at
//                           most one branch is viable at any position and the repetition cannot multiply.
//   Unproven               — neither proof reads the alternation (a quantified branch, a zero-width head, a
//                           nested group, an empty branch, or first characters that intersect): refuse.
enum class RegexAlternationProof
{
    Unproven,
    DisjointWholeFootprint,
    DisjointFirstChar
};

// The selector, M2-c first: the whole-footprint proof answers with the least reading, so every alternation it
// could already rule keeps round 5's verdict; the first-character proof only widens what is provable for the
// branches the whole-footprint proof always refused unread.
inline RegexAlternationProof regexAlternationProof( const std::string& pat, std::size_t bodyBegin, std::size_t closeAt, const std::vector<std::size_t>& pipes )
{
    std::vector<std::pair<std::size_t, std::size_t>> spans;
    regexTopLevelBranchSpans( bodyBegin, closeAt, pipes, spans );

    {   // M2-c — the whole footprint of every branch, and all of them pairwise disjoint
        std::vector<RegexCharSet> whole;
        whole.reserve( spans.size() );
        bool allRead = true;
        for( const auto [ begin, end ] : spans )
        {
            RegexCharSet set;
            if( !regexCharSetOfSingleCharBranch( pat, begin, end, set ) )
            {
                allRead = false;
                break;
            }
            whole.push_back( set );
        }
        if( allRead )
        {
            bool pairwiseDisjoint = true;
            for( std::size_t a = 0; a < whole.size() && pairwiseDisjoint; ++a )
            {
                for( std::size_t b = a + 1; b < whole.size(); ++b )
                {
                    if( regexCharSetsIntersect( whole[ a ], whole[ b ] ) )
                    {
                        pairwiseDisjoint = false;
                        break;
                    }
                }
            }
            if( pairwiseDisjoint )
            {
                return RegexAlternationProof::DisjointWholeFootprint;
            }
        }
    }

    {   // M2-e — the first character of every branch, the branch an unquantified width-one sequence
        std::vector<RegexCharSet> firsts;
        firsts.reserve( spans.size() );
        for( const auto [ begin, end ] : spans )
        {
            RegexCharSet first;
            if( !regexFirstCharSetOfQuantifierFreeBranch( pat, begin, end, first ) )
            {
                return RegexAlternationProof::Unproven;
            }
            firsts.push_back( first );
        }
        for( std::size_t a = 0; a < firsts.size(); ++a )
        {
            for( std::size_t b = a + 1; b < firsts.size(); ++b )
            {
                if( regexCharSetsIntersect( firsts[ a ], firsts[ b ] ) )
                {
                    return RegexAlternationProof::Unproven;
                }
            }
        }
        return RegexAlternationProof::DisjointFirstChar;
    }
}

// One frame per OPEN group. M2-c replaced the bare flag vector with a frame because the alternation arm needs
// two more things about a group: where its own BODY starts (a group modifier is not body), and where its OWN
// top-level '|' characters are — a '|' inside a nested group belongs to that group, not to this one, and
// treating it as this group's would split a branch in the wrong place. File scope, not a local of the scan
// below, because regexCloseGroup (which owns the group-close verdict) reads and writes these too.
// M2-d adds the second travelling flag: hasUnprovenAlternationInside, set on a parent when a group it encloses
// closes with a top-level '|' the screen could not prove disjoint, so a quantified ancestor the arm never saw
// still refuses (see regexCloseGroupVerdict's M2-d arm).
struct RegexGroupFrame
{
    bool                     hasQuantifierInside         = false;
    bool                     hasUnprovenAlternationInside = false;
    std::size_t              bodyBegin                    = 0;
    std::vector<std::size_t> topLevelPipes;
};

// What closing a group decides. M2-d: the verdict PLUS whether the group's OWN top-level alternation is one the
// screen cannot prove disjoint — a fact about the group's subtree that its parent must inherit even when the
// group itself closes under no quantifier (the paren bypass; regexCloseGroup folds it into the parent frame).
struct RegexGroupClose
{
    std::optional<std::string> refusal             = std::nullopt;
    bool                       unprovenAlternation = false;
};

// The verdict made when a group CLOSES, in two arms and in this order:
//   (1) a quantifier INSIDE the group, repeated by an unbounded quantifier ON the group — the (X+)+ family;
//   (2) M2-c's alternation arm, widened by M2-d: a group closing under an unbounded quantifier whose own
//       top-level branches the screen cannot prove disjoint — (a|a)+ — OR that carries the flag a NESTED
//       group set on its frame — ((a|aa))+ — refused with the same alternation sentence. The nested form is
//       the paren bypass closed: the inner group closed under no quantifier, so only this flag tells the
//       outer '+' it is repeating an alternation the screen never proved disjoint.
// Arm (2) runs ONLY when arm (1) has not refused, so every pattern refused before M2-c keeps the message it
// had (regexguardcheck.sh asserts that wording at every entry point). `unprovenAlternation` is true when the
// group's own top-level '|' exists and the screen could not prove its branches disjoint — a fact about the
// group's SUBTREE its parent must inherit whether or not this close refused, which regexCloseGroup folds.
inline RegexGroupClose regexCloseGroupVerdict( const std::string& pat, std::size_t closeAt, const RegexGroupFrame& frame )
{
    const RegexQuantifier quant = regexQuantifierAt( pat, closeAt + 1 );
    RegexGroupClose       out;
    // M2-c then M2-e, the selector above: the alternation is PROVEN DISJOINT when either proof passes — the
    // whole-footprint single-character proof, or the first-character proof for branches the first cannot read.
    // The whole-footprint proof keeps running FIRST so every verdict it already made stays byte-identical; the
    // first-character proof only widens what is proven for the branches it always refused unread.
    out.unprovenAlternation = !frame.topLevelPipes.empty()
        && regexAlternationProof( pat, frame.bodyBegin, closeAt, frame.topLevelPipes ) == RegexAlternationProof::Unproven;
    if( quant.isPresent && quant.isUnbounded && frame.hasQuantifierInside )
    {
        out.refusal = catastrophicRegexMessage( pat[ closeAt + 1 ] );
        return out;
    }
    if( quant.isPresent && quant.isUnbounded && ( out.unprovenAlternation || frame.hasUnprovenAlternationInside ) )
    {
        out.refusal = catastrophicRegexAlternationMessage( pat[ closeAt + 1 ] );
    }
    return out;
}

// A ')' in the scan: pop the frame, judge it (regexCloseGroupVerdict), fold its verdict into the parent group,
// and step `i` past the group's own quantifier so the scan does not re-read it. Returns the refusal when the
// group is catastrophic, else nullopt. `i` holds the ')' index on entry and the quantifier's last index on exit.
// Kept out of the scan loop so the loop reads as the small state machine it is.
inline std::optional<std::string> regexCloseGroup( const std::string& pat, std::size_t& i, std::vector<RegexGroupFrame>& frames )
{
    if( frames.empty() )
    {
        return std::nullopt; // unbalanced: the compile probe below owns that error
    }
    const RegexGroupFrame frame = std::move( frames.back() );
    frames.pop_back();

    const RegexGroupClose close = regexCloseGroupVerdict( pat, i, frame );
    if( close.refusal )
    {
        return close.refusal;
    }

    const RegexQuantifier quant = regexQuantifierAt( pat, i + 1 );
    // the group is now an ATOM of its parent: a quantifier anywhere inside it — or ON it — is a quantifier
    // inside the parent too, which is what makes ((a+))+, ((a)+)+ and ((a)?)+ visible
    if( !frames.empty() && ( frame.hasQuantifierInside || quant.isPresent ) )
    {
        frames.back().hasQuantifierInside = true;
    }
    // M2-d — and an alternation the screen could not prove disjoint travels the same way: this group's own
    // top-level '|' if the close could not prove it disjoint, or one a nested group already handed it. Whatever
    // quantified THIS group is beside the point; a QUANTIFIED ANCESTOR repeating this group repeats the
    // alternation, which is what ((a|aa))+b$ is and what the old arm, judging only an unbounded quantifier ON
    // the group itself, never saw.
    if( !frames.empty() && ( frame.hasUnprovenAlternationInside || close.unprovenAlternation ) )
    {
        frames.back().hasUnprovenAlternationInside = true;
    }
    if( quant.isPresent )
    {
        i += quant.lengthCount; // step over the quantifier we just judged
    }
    return std::nullopt;
}

inline std::optional<std::string> catastrophicRegexConstruct( const std::string& pat )
{
    std::vector<RegexGroupFrame> frames;
    bool                         isInsideClass = false;

    for( std::size_t i = 0; i < pat.size(); ++i )
    {
        const char c = pat[ i ];

        // the two contexts where a quantifier character is just a character
        if( c == '\\' )     { ++i; continue; }                                         // '\+' is a literal plus
        if( isInsideClass )
        {
            if( c == ']' )
            {
                isInsideClass = false;
            }
            continue;
        } // '[a+]' is a literal plus
        if( c == '[' )      { isInsideClass = true; continue; }

        // group open / close — the close is where the whole verdict is made
        if( c == '(' )
        {
            const std::size_t modifier = regexGroupModifierLength( pat, i );
            frames.push_back( { false, false, i + 1 + modifier, {} } );
            i += modifier;
            continue;
        }
        if( c == ')' )
        {
            if( std::optional<std::string> refusal = regexCloseGroup( pat, i, frames ) )
            {
                return refusal;
            }
            continue;
        }

        // this group's own top-level '|' — the separator the alternation arm splits its branches on
        if( c == '|' )
        {
            if( !frames.empty() )
            {
                frames.back().topLevelPipes.push_back( i );
            }
            continue;
        }

        // a plain quantifier: it marks the innermost enclosing group, if any (top-level repetition is fine)
        const RegexQuantifier quant = regexQuantifierAt( pat, i );
        if( quant.isPresent && !frames.empty() )
        {
            frames.back().hasQuantifierInside = true;
        }
        if( quant.isPresent )
        {
            i += quant.lengthCount - 1;
        }
    }
    return std::nullopt;
}

// ── STACK: both standard libraries' regex PARSERS recurse, so a long or deeply nested pattern overflows the stack ──
//
// Measured 2026-09-16 with a standalone probe (compile + destroy one pattern, binary search for the first signal death):
//
//     smallest crash            Apple libc++, std::thread (512 KiB)   libstdc++ 13, 8 MiB     libstdc++ 13, 512 KiB
//     nested groups  ((( a )))           3,392 deep                         15,616 deep             960 deep
//     literal atoms  aaaa…              16,896 bytes                        58,368 bytes          3,648 bytes
//     alternatives   a|a|…               8,448 alternatives           (NFA-state refusal first)        —
//
// A grep worker, an --arch/astquery compile thread and every other std::thread runs on the 512 KiB default on macOS,
// which is how `--regex=<20,000 bytes of a>` died with SIGBUS (rc 138) in a worker after the main thread's probe
// compile had passed it. So the screen bounds the pattern BEFORE any parser sees it: at most kRegexMaxPatternBytes
// bytes and kRegexMaxGroupDepth nested groups. Both sit under the smallest crash in every column above (the tightest,
// libstdc++ on a 512 KiB stack, by 1.78x on bytes and 15x on depth), are far above any pattern this tree's gates or
// rule tables write, and are one verdict on every platform. The MATCHER is a different story on libstdc++ — its DFS
// executor recurses per consumed character — and a pattern bound cannot reach it; that residual is disclosed in the
// lane report, not claimed fixed here.
inline constexpr std::size_t kRegexMaxPatternBytes = 2048;   // a longer pattern is REFUSED by name, never truncated — the compile-recursion stack bound
inline constexpr std::size_t kRegexMaxGroupDepth   = 64;     // deeper group nesting is REFUSED by name — the same stack bound, for nesting

inline std::optional<std::string> regexSizeRefusal( const std::string& pattern )
{
    if( pattern.size() > kRegexMaxPatternBytes )
    {
        return "the pattern is " + std::to_string( pattern.size() ) + " bytes and the limit is " + std::to_string( kRegexMaxPatternBytes )
             + ": std::regex compiles by recursion, and a longer pattern can overflow a worker thread's stack (a 16,896-byte literal "
               "killed a 512 KiB libc++ thread, a 3,648-byte one a libstdc++ thread of the same size) — split it into several shorter "
               "patterns or searches";
    }
    std::size_t depth = 0, deepest = 0;
    bool        isInsideClass = false;
    for( std::size_t i = 0; i < pattern.size(); ++i )
    {
        const char c = pattern[i];
        if( c == '\\' )
        {
            ++i;
            continue;
        }
        if( isInsideClass )
        {
            isInsideClass = ( c != ']' );
            continue;
        }
        isInsideClass = ( c == '[' );
        depth         = ( c == '(' ) ? depth + 1 : ( c == ')' && depth > 0 ) ? depth - 1 : depth;
        deepest       = std::max( deepest, depth );
    }
    if( deepest > kRegexMaxGroupDepth )
    {
        return "groups nest " + std::to_string( deepest ) + " deep and the limit is " + std::to_string( kRegexMaxGroupDepth )
             + ": std::regex compiles nested groups by recursion, and a deeper pattern can overflow a worker thread's stack (960 nested "
               "groups killed a 512 KiB libstdc++ thread) — flatten the nesting";
    }
    return std::nullopt;
}

// The structural screens, in order: the size bounds first (the stack reason above, and cheap), then the two
// `--regex` has always applied — the portability screen (L5), then the backtracking screen (M2). A pure function of
// the pattern TEXT, so every verdict is the same on every standard library.
inline std::optional<std::string> screenRegexPattern( const std::string& pattern ) noexcept
{
    if( std::optional<std::string> size = regexSizeRefusal( pattern ) )
    {
        return size;
    }
    if( std::optional<std::string> portability = nonPortableRegexEscape( pattern ) )
    {
        return portability;
    }
    return catastrophicRegexConstruct( pattern );
}

// ── the vocabulary a call site spells instead of the standard library's ─────────────────────────────────────
using RegexSyntax   = std::regex_constants::syntax_option_type;
using RegexCaptures = std::cmatch;   // captures over a std::string_view subject; the subject must outlive them

inline constexpr RegexSyntax kRegexEcmaScript = std::regex_constants::ECMAScript;   // std::regex's own default
inline constexpr RegexSyntax kRegexOptimize   = std::regex_constants::optimize;
inline constexpr RegexSyntax kRegexIcase      = std::regex_constants::icase;

enum class RegexVerdict : std::uint8_t
{
    Miss,
    Hit,
    Exhausted,   // the engine gave up DURING the match (regex_error or bad_alloc) — the answer is unknown, never a miss
    Skipped,     // the subject was never handed to the engine — longer than this thread's measured-safe bound; unknown, never a miss
};

// The one sentence every entry point quotes when a match is abandoned, so a reader (and a gate) meets the same
// words whichever verb it asked. Platform-independent on purpose: the engine's own what() differs per standard
// library, and this refusal must read the same on every one that can produce it.
inline constexpr std::string_view kRegexAbandonedReason =
    "the regex engine abandoned the match (std::regex gave up part-way through it: the backtracking a structural "
    "screen cannot see — a crafted subject under a pattern the screen admits — or its stack or memory limit)";

// The counterpart for RegexVerdict::Skipped — the sentence every entry point quotes when a subject was never
// handed to the engine at all (too long for this thread's measured-safe bound, src/infra/stackthreads.h and
// maxEngineSubjectBytes below). Distinct from kRegexAbandonedReason on purpose: "gave up mid-match" points a
// reader at the pattern's backtracking; "too long to try" points them at the subject's size instead.
inline constexpr std::string_view kRegexOversizeReason =
    "the subject was too long for the regex engine to attempt safely on this thread (longer than the measured-safe "
    "bound for this pattern's recursion cost and stack size)";

// ── THE PATTERN'S SHAPE, read once when it compiles ─────────────────────────────────────────────────────────────
//
// libstdc++'s matcher is a depth-first search that RECURSES once for every state it steps through, so a match that
// consumes a long run recurses once per byte or more: on Linux's 8 MiB stack `--regex='a*b'` died with SIGSEGV on a
// matching line of about 26 KB (27–45 KB across this tool's own gcc and clang builds). No pattern bound reaches
// that — the depth is set by the SUBJECT. Three facts about the pattern let a match avoid the engine or bound it:
//
//   1. THE LITERAL PLAN. A pattern that is one literal, or an alternation of literals (one literal may carry `^`
//      and `$`), matches exactly where a byte search finds it, in the engine's own order: leftmost start first,
//      and at one start the first alternative written. Nothing recurses and no line is too long for it.
//   2. THE REQUIRED LITERALS. Every match of `foo.*bar` contains "foo": a run of plain literal bytes with no
//      quantifier on any of them, outside every group, in each top-level alternative. A subject holding none of
//      an alternation's runs cannot match, so the engine is never asked. Under icase the runs are ASCII-lowered
//      and compared folded, and only while the global locale is the classic one — std::regex folds through the
//      locale the regex was built under, and the classic locale folds A–Z and nothing else.
//   3. THE RECURSION COST. An upper bound on how many states libstdc++'s matcher can have on its stack for a
//      subject of N bytes, `fixedVisits + visitsPerByte × N`, which the caller turns into the longest subject
//      its thread's stack can take (maxEngineSubjectBytes).
//
// The reader below is conservative, not a second regex parser: a token it cannot vouch for (a bracket nested in a
// class, a `{` that is not a quantifier, a bare `]` or `}`) ends the literal plan and the required run, and still
// counts as a state for the cost. test/regexguardcheck.sh arm (j) runs every fact against the engine itself.

enum class RegexTokenKind : std::uint8_t
{
    Literal,         // one byte that matches only itself
    Atom,            // consumes one byte some other way: `.`, a class, `\d`, `\xHH`, or a byte this reader will not vouch for
    Assertion,       // zero width: ^ $ \b \B
    Backref,         // \1 …: consumes what a group captured, possibly nothing
    GroupOpen,       // ( or (?:
    LookaheadOpen,   // (?= or (?!
    GroupClose,
    Alternation,
    Quantifier,
};

inline constexpr std::uint64_t kRegexCountCap = std::uint64_t( 1 ) << 40;   // state counts saturate here, far past any stack

struct RegexToken
{
    RegexTokenKind kind        = RegexTokenKind::Atom;
    std::size_t    lengthCount = 1;
    char           literal     = 0;               // Literal only
    bool           isVouched   = true;            // false ⇒ the literal plan and the required run stop here
    std::uint64_t  minCount    = 0;               // Quantifier only
    std::uint64_t  maxCount    = 0;               // Quantifier only; kRegexCountCap when unbounded
};

inline std::uint64_t regexCountAdd( std::uint64_t a, std::uint64_t b ) noexcept { return std::min( a + b, kRegexCountCap ); }
inline std::uint64_t regexCountMul( std::uint64_t a, std::uint64_t b ) noexcept
{
    return ( a == 0 || b == 0 ) ? 0 : ( a > kRegexCountCap / b ) ? kRegexCountCap : std::min( a * b, kRegexCountCap );
}

// A character class from its `[` to one past its `]`. ECMAScript closes on the first unescaped `]`, even straight after
// `[` or `[^` (`[]` is the empty class on both standard libraries); `[:alpha:]`-style names are stepped over whole. A
// `[` inside the class makes the token unvouched: the two libraries do not read nested brackets the same way.
inline RegexToken regexClassTokenAt( const std::string& pat, std::size_t at ) noexcept
{
    RegexToken  token;
    std::size_t i = at + 1;
    if( i < pat.size() && pat[ i ] == '^' )
    {
        ++i;
    }
    while( i < pat.size() )
    {
        if( pat[ i ] == '\\' )
        {
            i += 2;
            continue;
        }
        if( pat[ i ] == '[' )
        {
            token.isVouched = false;
            const bool isNamed = i + 1 < pat.size() && ( pat[ i + 1 ] == ':' || pat[ i + 1 ] == '.' || pat[ i + 1 ] == '=' );
            const std::size_t close = isNamed ? pat.find( std::string{ pat[ i + 1 ], ']' }, i + 2 ) : std::string::npos;
            i = ( close == std::string::npos ) ? i + 1 : close + 2;
            continue;
        }
        if( pat[ i ] == ']' )
        {
            token.lengthCount = i + 1 - at;
            return token;
        }
        ++i;
    }
    token.lengthCount = std::max<std::size_t>( pat.size() - at, 1 );
    token.isVouched   = false;
    return token;
}

inline RegexToken regexEscapeTokenAt( const std::string& pat, std::size_t at ) noexcept
{
    RegexToken token;
    if( at + 1 >= pat.size() )
    {
        token.isVouched = false;
        return token;
    }
    const char escaped = pat[ at + 1 ];
    token.lengthCount  = 2;
    switch( escaped )
    {
    case 'b': case 'B':
        token.kind = RegexTokenKind::Assertion;
        return token;
    case 'd': case 'D': case 's': case 'S': case 'w': case 'W': case '0':
        return token;
    case 'f': token.kind = RegexTokenKind::Literal; token.literal = '\f'; return token;
    case 'n': token.kind = RegexTokenKind::Literal; token.literal = '\n'; return token;
    case 'r': token.kind = RegexTokenKind::Literal; token.literal = '\r'; return token;
    case 't': token.kind = RegexTokenKind::Literal; token.literal = '\t'; return token;
    case 'v': token.kind = RegexTokenKind::Literal; token.literal = '\v'; return token;
    case 'c': token.lengthCount = std::min<std::size_t>( 3, pat.size() - at ); return token;
    case 'x': token.lengthCount = std::min<std::size_t>( 4, pat.size() - at ); return token;
    case 'u': token.lengthCount = std::min<std::size_t>( 6, pat.size() - at ); return token;
    default:
        break;
    }
    if( escaped >= '1' && escaped <= '9' )
    {
        token.kind = RegexTokenKind::Backref;
        while( at + token.lengthCount < pat.size() && pat[ at + token.lengthCount ] >= '0' && pat[ at + token.lengthCount ] <= '9' )
        {
            ++token.lengthCount;
        }
        return token;
    }
    const unsigned char byte          = static_cast<unsigned char>( escaped );
    const bool          isPunctuation = byte > 0x20 && byte < 0x7F && byte != '_' && !( byte >= '0' && byte <= '9' )
                                        && !( ( byte | 0x20 ) >= 'a' && ( byte | 0x20 ) <= 'z' );
    if( isPunctuation )
    {
        token.kind    = RegexTokenKind::Literal;                      // an identity escape: `\.` is a dot, on both libraries
        token.literal = escaped;
        return token;
    }
    token.isVouched = false;
    return token;
}

inline RegexToken regexTokenAt( const std::string& pat, std::size_t at ) noexcept
{
    RegexToken token;
    const char c = pat[ at ];
    switch( c )
    {
    case '(':
        token.kind = RegexTokenKind::GroupOpen;
        if( at + 2 < pat.size() && pat[ at + 1 ] == '?' )
        {
            const char kind   = pat[ at + 2 ];
            token.kind        = ( kind == '=' || kind == '!' ) ? RegexTokenKind::LookaheadOpen : RegexTokenKind::GroupOpen;
            token.lengthCount = ( kind == '=' || kind == '!' || kind == ':' ) ? 3 : 1;
            token.isVouched   = ( kind == '=' || kind == '!' || kind == ':' );
        }
        return token;
    case ')': token.kind = RegexTokenKind::GroupClose;  return token;
    case '|': token.kind = RegexTokenKind::Alternation; return token;
    case '^': case '$': token.kind = RegexTokenKind::Assertion; return token;
    case '.': return token;
    case '[': return regexClassTokenAt( pat, at );
    case '\\': return regexEscapeTokenAt( pat, at );
    case ']': case '}': case '\0':
        token.isVouched = false;
        return token;
    case '*': case '+': case '?': case '{':
    {
        const RegexQuantifier quant = regexQuantifierAt( pat, at );
        if( !quant.isPresent )
        {
            token.isVouched = false;                                   // a `{` that is not an interval
            return token;
        }
        token.kind        = RegexTokenKind::Quantifier;
        token.lengthCount = quant.lengthCount;
        token.minCount    = ( c == '+' ) ? 1 : 0;
        token.maxCount    = ( c == '?' ) ? 1 : kRegexCountCap;
        if( c == '{' )
        {
            std::size_t cursor = at + 1;
            std::uint64_t lower = 0, upper = 0;
            for( ; pat[ cursor ] >= '0' && pat[ cursor ] <= '9'; ++cursor ) { lower = std::min( lower * 10 + std::uint64_t( pat[ cursor ] - '0' ), kRegexCountCap ); }
            token.minCount = lower;
            token.maxCount = quant.isUnbounded ? kRegexCountCap : lower;
            if( pat[ cursor ] == ',' && !quant.isUnbounded )
            {
                for( ++cursor; pat[ cursor ] >= '0' && pat[ cursor ] <= '9'; ++cursor ) { upper = std::min( upper * 10 + std::uint64_t( pat[ cursor ] - '0' ), kRegexCountCap ); }
                token.maxCount = std::max( upper, lower );
            }
        }
        if( at + token.lengthCount < pat.size() && pat[ at + token.lengthCount ] == '?' )
        {
            ++token.lengthCount;                                       // lazy: the same states, visited in another order
        }
        return token;
    }
    default:
        token.kind    = RegexTokenKind::Literal;
        token.literal = c;
        return token;
    }
}

// ── 1. the literal plan ─────────────────────────────────────────────────────────────────────────────────────────
struct RegexLiteralPlan
{
    std::vector<std::string> alternatives;              // in pattern order; empty ⇒ no plan
    bool                     isAnchoredBegin = false;   // `^lit` (one alternative only)
    bool                     isAnchoredEnd   = false;   // `lit$` (one alternative only)
    bool                     isLineFree      = false;   // unanchored, and no alternative holds '\n' or '\r'
};

inline RegexLiteralPlan regexLiteralPlanOf( const std::string& pat, RegexSyntax syntax ) noexcept
{
    RegexLiteralPlan plan;
    if( ( syntax & ~( kRegexEcmaScript | kRegexOptimize | std::regex_constants::nosubs ) ) != RegexSyntax{} || pat.empty() )
    {
        return plan;
    }
    std::size_t at = 0;
    plan.isAnchoredBegin = pat[ 0 ] == '^';
    at += plan.isAnchoredBegin ? 1 : 0;
    std::vector<std::string> alternatives( 1 );
    while( at < pat.size() )
    {
        const RegexToken token = regexTokenAt( pat, at );
        const std::size_t next = at + token.lengthCount;
        if( token.kind == RegexTokenKind::Literal && token.isVouched
            && !( next < pat.size() && regexTokenAt( pat, next ).kind == RegexTokenKind::Quantifier ) )
        {
            alternatives.back().push_back( token.literal );
        }
        else if( token.kind == RegexTokenKind::Alternation )
        {
            alternatives.emplace_back();
        }
        else if( token.kind == RegexTokenKind::Assertion && pat[ at ] == '$' && next == pat.size() )
        {
            plan.isAnchoredEnd = true;
        }
        else
        {
            return plan;
        }
        at = next;
    }
    const bool hasEmpty = std::any_of( alternatives.begin(), alternatives.end(), []( const std::string& a ) { return a.empty(); } );
    if( hasEmpty || ( ( plan.isAnchoredBegin || plan.isAnchoredEnd ) && alternatives.size() > 1 ) )
    {
        return RegexLiteralPlan{};
    }
    plan.isLineFree   = !plan.isAnchoredBegin && !plan.isAnchoredEnd
                      && std::none_of( alternatives.begin(), alternatives.end(),
                                       []( const std::string& a ) { return a.find_first_of( "\r\n" ) != std::string::npos; } );
    plan.alternatives = std::move( alternatives );
    return plan;
}

// ── 2. the required literals ────────────────────────────────────────────────────────────────────────────────────
struct RegexRequiredLiterals
{
    std::vector<std::string> anyOf;                  // empty ⇒ no prefilter; else every match contains one of these
    bool                     isCaseFolded = false;   // ASCII-lowered, compared folded (icase under the classic locale)
    bool                     isLineFree   = false;   // not folded, and no literal holds '\n' or '\r' (the whole-text jump)
};

inline RegexRequiredLiterals regexRequiredLiteralsOf( const std::string& pat, RegexSyntax syntax ) noexcept
{
    RegexRequiredLiterals out;
    const bool isFolded = ( syntax & kRegexIcase ) != RegexSyntax{};
    if( ( syntax & ~( kRegexEcmaScript | kRegexOptimize | kRegexIcase | std::regex_constants::nosubs ) ) != RegexSyntax{}
        || ( isFolded && std::locale() != std::locale::classic() ) )
    {
        return out;
    }
    std::vector<std::string> anyOf;
    std::string              best, run;
    const auto               commit = [ & ] { if( run.size() > best.size() ) { best = run; } run.clear(); };
    const auto               finish = [ & ] { commit(); anyOf.push_back( std::move( best ) ); best.clear(); };
    std::size_t              at     = 0;
    while( at < pat.size() )
    {
        const RegexToken token = regexTokenAt( pat, at );
        std::size_t      next  = at + token.lengthCount;
        if( !token.isVouched || token.kind == RegexTokenKind::GroupClose )
        {
            return out;                                                  // unreadable here, or unbalanced: no prefilter
        }
        const bool isQuantified = next < pat.size() && regexTokenAt( pat, next ).kind == RegexTokenKind::Quantifier;
        switch( token.kind )
        {
        case RegexTokenKind::Literal:
            if( isQuantified )
            {
                commit();
            }
            else
            {
                const char byte = token.literal;
                run.push_back( ( isFolded && byte >= 'A' && byte <= 'Z' ) ? char( byte + 0x20 ) : byte );
            }
            break;
        case RegexTokenKind::Alternation:
            finish();
            break;
        case RegexTokenKind::GroupOpen:
        case RegexTokenKind::LookaheadOpen:
        {
            commit();
            std::size_t depth = 1;                                       // step over the group whole
            while( next < pat.size() && depth > 0 )
            {
                const RegexToken inner = regexTokenAt( pat, next );
                if( !inner.isVouched )
                {
                    return out;
                }
                depth += ( inner.kind == RegexTokenKind::GroupOpen || inner.kind == RegexTokenKind::LookaheadOpen ) ? 1 : 0;
                depth -= ( inner.kind == RegexTokenKind::GroupClose ) ? 1 : 0;
                next  += inner.lengthCount;
            }
            if( depth != 0 )
            {
                return out;
            }
            break;
        }
        default:
            commit();                                                    // an atom, an assertion, a backref, a quantifier
            break;
        }
        at = next;
    }
    finish();
    if( std::any_of( anyOf.begin(), anyOf.end(), []( const std::string& s ) { return s.empty(); } ) )
    {
        return out;
    }
    out.isCaseFolded = isFolded;
    out.isLineFree   = !isFolded && std::none_of( anyOf.begin(), anyOf.end(),
                                                  []( const std::string& s ) { return s.find_first_of( "\r\n" ) != std::string::npos; } );
    out.anyOf        = std::move( anyOf );
    return out;
}

// ── 3. the recursion cost ───────────────────────────────────────────────────────────────────────────────────────
//
// What libstdc++'s executor does (bits/regex_executor.tcc, _M_dfs and its handlers): every state it steps into is a
// nested call, and a call returns only when that branch is decided. So the stack holds the current PATH from the
// start state. On that path:
//   * a state on no cycle appears at most once — only an unbounded repeat (`*`, `+`, `{n,}`) closes a cycle;
//   * the subject position never moves backwards, and each consuming state moves it by one byte;
//   * at one position, a repeat state descends into its body at most twice (_M_rep_once_more's count is saved and
//     restored only when the frame unwinds), so a state on a cycle appears at most 2 + 1 + 2 = 5 times per position:
//     two descents, one entry by consuming the previous byte, and (for the repeat state itself) two loop-backs;
//   * a lookahead runs a separate executor nested on the same stack, which returns before the path continues.
// So for a subject of N bytes the path is at most  T + N + 5·C·(N + 1)  states, T = every state and C = the
// non-consuming states on a cycle, plus the deepest lookahead's own bound. The model below uses 6 for that 5, a
// margin against a counting slip, and test/regexguardcheck.sh arm (l) measures the real depth on the real engine.
struct RegexRecursionCost
{
    std::uint64_t fixedVisits   = 0;
    std::uint64_t visitsPerByte = 0;
};

inline constexpr std::uint64_t kRegexVisitsPerCycleState = 6;
inline constexpr std::uint64_t kRegexLookaheadFrameVisits = 8;   // the nested executor object lives in the lookahead's frame

struct RegexShapeCount
{
    std::uint64_t states       = 0;   // every NFA state on the outer path, clones counted
    std::uint64_t nonConsuming = 0;   // states that do not advance the subject by exactly one byte
    std::uint64_t cycleStates  = 0;   // non-consuming states inside an unbounded repeat, the repeat state included
    std::uint64_t lookFixed    = 0;   // the deepest lookahead's own bound: fixed…
    std::uint64_t lookPerByte  = 0;   // …and per subject byte
};

inline RegexShapeCount regexShapeSequence( const RegexShapeCount& a, const RegexShapeCount& b ) noexcept
{
    return { regexCountAdd( a.states, b.states ), regexCountAdd( a.nonConsuming, b.nonConsuming ), regexCountAdd( a.cycleStates, b.cycleStates ),
             std::max( a.lookFixed, b.lookFixed ), std::max( a.lookPerByte, b.lookPerByte ) };
}

inline RegexShapeCount regexShapeRepeat( const RegexShapeCount& body, std::uint64_t minCount, std::uint64_t maxCount ) noexcept
{
    RegexShapeCount out = body;
    if( maxCount >= kRegexCountCap )
    {
        const std::uint64_t copies = regexCountAdd( minCount, 1 );    // n plain copies, then one looped copy and its repeat state
        out.states       = regexCountAdd( regexCountMul( body.states, copies ), 1 );
        out.nonConsuming = regexCountAdd( regexCountMul( body.nonConsuming, copies ), 1 );
        out.cycleStates  = regexCountAdd( regexCountAdd( regexCountMul( body.cycleStates, minCount ), body.nonConsuming ), 1 );
        return out;
    }
    const std::uint64_t optional = maxCount - std::min( minCount, maxCount );
    out.states       = regexCountAdd( regexCountMul( body.states, maxCount ), optional );
    out.nonConsuming = regexCountAdd( regexCountMul( body.nonConsuming, maxCount ), optional );
    out.cycleStates  = regexCountMul( body.cycleStates, maxCount );
    return out;
}

inline RegexShapeCount regexShapeDisjunction( const std::string& pat, std::size_t& at, bool isNested ) noexcept;

inline RegexShapeCount regexShapeAlternative( const std::string& pat, std::size_t& at, bool isNested ) noexcept
{
    RegexShapeCount acc;
    while( at < pat.size() )
    {
        const RegexToken token = regexTokenAt( pat, at );
        if( token.kind == RegexTokenKind::Alternation || ( token.kind == RegexTokenKind::GroupClose && isNested ) )
        {
            break;
        }
        at += token.lengthCount;
        RegexShapeCount term;
        switch( token.kind )
        {
        case RegexTokenKind::Literal:
        case RegexTokenKind::Atom:
            term = { 1, 0, 0, 0, 0 };
            break;
        case RegexTokenKind::GroupOpen:
        case RegexTokenKind::LookaheadOpen:
        {
            const RegexShapeCount inner = regexShapeDisjunction( pat, at, /*isNested=*/true );
            at += ( at < pat.size() && pat[ at ] == ')' ) ? 1 : 0;
            if( token.kind == RegexTokenKind::GroupOpen )
            {
                term = regexShapeSequence( inner, { 2, 2, 0, 0, 0 } );
                break;
            }
            const std::uint64_t cycleVisits = regexCountMul( kRegexVisitsPerCycleState, inner.cycleStates );
            term.states       = 1;
            term.nonConsuming = 1;
            term.lookFixed    = regexCountAdd( regexCountAdd( regexCountAdd( inner.states, 1 ), cycleVisits ),
                                               regexCountAdd( kRegexLookaheadFrameVisits, inner.lookFixed ) );
            term.lookPerByte  = regexCountAdd( inner.cycleStates > 0 ? regexCountAdd( cycleVisits, 1 ) : 0, inner.lookPerByte );
            break;
        }
        default:                                                     // an assertion, a backref, a stray `)` or quantifier
            term = { 1, 1, 0, 0, 0 };
            break;
        }
        while( at < pat.size() )
        {
            const RegexToken quant = regexTokenAt( pat, at );
            if( quant.kind != RegexTokenKind::Quantifier )
            {
                break;
            }
            term = regexShapeRepeat( term, quant.minCount, quant.maxCount );
            at  += quant.lengthCount;
        }
        acc = regexShapeSequence( acc, term );
    }
    return acc;
}

inline RegexShapeCount regexShapeDisjunction( const std::string& pat, std::size_t& at, bool isNested ) noexcept
{
    RegexShapeCount total = regexShapeAlternative( pat, at, isNested );
    while( at < pat.size() && pat[ at ] == '|' )
    {
        ++at;
        total = regexShapeSequence( regexShapeSequence( total, regexShapeAlternative( pat, at, isNested ) ), { 2, 2, 0, 0, 0 } );
    }
    return total;
}

inline RegexRecursionCost regexRecursionCostOf( const std::string& pat ) noexcept
{
    std::size_t           at          = 0;
    const RegexShapeCount shape       = regexShapeDisjunction( pat, at, /*isNested=*/false );   // a stray top-level `)` reads as one more state
    const std::uint64_t   cycleVisits = regexCountMul( kRegexVisitsPerCycleState, shape.cycleStates );
    RegexRecursionCost    cost;
    cost.fixedVisits   = regexCountAdd( regexCountAdd( regexCountAdd( shape.states, 3 ), cycleVisits ), shape.lookFixed );
    cost.visitsPerByte = regexCountAdd( shape.cycleStates > 0 ? regexCountAdd( cycleVisits, 1 ) : 0, shape.lookPerByte );
    return cost;
}

struct RegexCompile;

// ── the engine's stack, per standard library ────────────────────────────────────────────────────────────────────
//
// libstdc++ recurses once per state visit (the cost model above); libc++ keeps its matcher's states in a heap vector
// and recurses only into a lookahead, by pattern nesting, so no subject is too long for its stack (measured: `a*b` and
// `(a|b)*c` on a 512 KiB libc++ thread did not crash on any subject length, they were only slow). An unknown library is
// assumed to recurse.
#if defined( _LIBCPP_VERSION )
inline constexpr bool kRegexEngineRecursesPerVisit = false;
#else
inline constexpr bool kRegexEngineRecursesPerVisit = true;
#endif

// Stack bytes one MODELLED visit can take on libstdc++ 13 (_M_dfs, the handler it dispatches to, _M_rep_once_more).
// MEASURED, not derived: for 35 shapes (plain and lazy repeats, 1- to 16-way alternation loops, nested and non-capturing
// groups, \b/\B/$ inside loops, lookaheads, a backreference loop) the smallest crashing subject on an 8 MiB thread gives
// stack ÷ ( crash length × visitsPerByte ). The largest over gcc -O0/-O2, clang -O2 and -O3 -flto, and gcc and clang
// under -fsanitize=address was 100.7 (gcc -O2 ASan, `a*b`); the next was 63.3 (clang -O3 -flto). Rounded up to 128.
// Half of every stack is held back on top of this, so the engine's measured crash sits at 2 × 128 ÷ 100.7 = 2.5× the
// bound or further; at 256 MiB `a*b` was run at twice its bound on all three of those builds without a crash.
inline constexpr std::uint64_t kRegexStackBytesPerVisit = 128;
inline constexpr std::uint64_t kRegexStackReserveBytes  = 256 * 1024;   // the frames below the match: the scan, the worker, regex_search

// A caller off a sized thread bounds its subjects by kCallerStackBytesFloor (src/infra/stackthreads.h). Under libstdc++ that
// floor must leave the engine a real budget after the half held back and the reserve. At 512 KiB it left 0 visits, so every
// subject was Skipped on Linux (CI on #283). Asserted on the libstdc++ number on EVERY platform, so a macOS build refuses
// the regression too: at least 16,384 visits, which is a few thousand bytes of subject for a simple loop.
inline constexpr std::uint64_t kRegexCallerFloorVisitsMin = 16384;
static_assert( ( kCallerStackBytesFloorLibstdcxx / 2 > kRegexStackReserveBytes )
                   && ( kCallerStackBytesFloorLibstdcxx / 2 - kRegexStackReserveBytes ) / kRegexStackBytesPerVisit >= kRegexCallerFloorVisitsMin,
               "kCallerStackBytesFloor under libstdc++ leaves the regex engine no subject budget: every caller-thread match would be Skipped" );

// How a line scan treats the engine. `engineLineBytesMax` is the longest line the engine may be handed on this thread
// (maxEngineSubjectBytes of its stack); a longer one is SKIPPED and counted, never matched. `useLiteralPaths` false sends
// every line to the engine — the oracle a gate diffs the literal paths against (--no-prefilter).
struct RegexLinePolicy
{
    std::size_t engineLineBytesMax = SIZE_MAX;
    bool        useLiteralPaths    = true;
};

struct RegexLineScan
{
    RegexVerdict  verdict          = RegexVerdict::Miss;
    std::uint32_t skippedLineCount = 0;   // lines longer than engineLineBytesMax that could have matched: never matched
};

// The longest subject the engine may be handed on a thread whose stack is `stackBytes`: SIZE_MAX where the engine does not
// recurse per visit (libc++) or where this pattern's recursion does not grow with the subject.
inline std::size_t regexMaxSubjectBytes( const RegexRecursionCost& cost, std::size_t stackBytes ) noexcept
{
    if( !kRegexEngineRecursesPerVisit )
    {
        return SIZE_MAX;
    }
    const std::uint64_t half   = stackBytes / 2;
    const std::uint64_t visits = ( half > kRegexStackReserveBytes ? half - kRegexStackReserveBytes : 0 ) / kRegexStackBytesPerVisit;
    if( visits <= cost.fixedVisits )
    {
        return 0;
    }
    return cost.visitsPerByte == 0 ? SIZE_MAX : std::size_t( ( visits - cost.fixedVisits ) / cost.visitsPerByte );
}

// ── the literal paths: byte search, in the engine's own order ──────────────────────────────────────────────────────

// The first occurrence of `literal` in [p, p + n), or n. strkern's byte kernels find a candidate; the rest is compared.
inline std::size_t regexFindLiteral( const char* p, std::size_t n, const std::string& literal ) noexcept
{
    const std::size_t m = literal.size();
    if( m > n )
    {
        return n;
    }
    if( m < 3 )
    {
        for( std::size_t k = 0; k + m <= n; ++k )
        {
            const std::size_t at = k + strkern::findByte( p + k, n - m + 1 - k, literal[ 0 ] );
            if( at > n - m )
            {
                return n;
            }
            if( m == 1 || p[ at + 1 ] == literal[ 1 ] )
            {
                return at;
            }
            k = at;
        }
        return n;
    }
    const std::size_t span = n - m + 3;                                 // a 3-byte head found below span leaves room for the tail
    for( std::size_t k = 0; k + m <= n; ++k )
    {
        const std::size_t at = k + strkern::find3( p + k, span - k, literal.data() );
        if( at >= span )
        {
            return n;
        }
        if( std::memcmp( p + at + 3, literal.data() + 3, m - 3 ) == 0 )
        {
            return at;
        }
        k = at;
    }
    return n;
}

// Whether [p, p + n) holds `lowered` compared ASCII-folded (the icase required literal).
inline bool regexHoldsFoldedLiteral( const char* p, std::size_t n, const std::string& lowered ) noexcept
{
    const std::size_t m = lowered.size();
    if( m > n )
    {
        return false;
    }
    strkern::Byteset256 head;
    const unsigned char first = static_cast<unsigned char>( lowered[ 0 ] );
    head.add( first );
    head.add( ( first >= 'a' && first <= 'z' ) ? static_cast<unsigned char>( first - 0x20 ) : first );
    for( std::size_t k = 0; k + m <= n; ++k )
    {
        k += strkern::findByteset( p + k, n - m + 1 - k, head );
        if( k + m > n )
        {
            return false;
        }
        if( strkern::lowerFoldedEquals( p + k, lowered.data(), m ) )
        {
            return true;
        }
    }
    return false;
}

// A compiled pattern's literal plan and required literals, and the searches that use them.
struct RegexLiteralPaths
{
    RegexLiteralPlan      plan;
    strkern::Byteset256   planHeads;   // the first byte of every plan alternative
    RegexRequiredLiterals required;

    bool hasPlan() const noexcept { return !plan.alternatives.empty(); }

    // The first occurrence of any required literal in [p, p + n), or n (not folded: the whole-text jump).
    std::size_t findRequired( const char* p, std::size_t n ) const noexcept
    {
        std::size_t first = n;
        for( const std::string& literal : required.anyOf )
        {
            first = std::min( first, regexFindLiteral( p, first == n ? n : std::min( n, first + literal.size() ), literal ) );
        }
        return first;
    }

    bool holdsRequired( const char* p, std::size_t n ) const noexcept
    {
        return required.anyOf.empty()
            || std::any_of( required.anyOf.begin(), required.anyOf.end(), [ & ]( const std::string& literal )
                            { return required.isCaseFolded ? regexHoldsFoldedLiteral( p, n, literal ) : regexFindLiteral( p, n, literal ) < n; } );
    }

    bool findsPlanMatch( const char* p, std::size_t n ) const noexcept
    {
        bool isFound = false;
        forEachPlanMatch( p, n, [ & ]( std::size_t ) { isFound = true; return false; } );
        return isFound;
    }

    // The plan's matches in [p, p + n), non-overlapping, leftmost start first and at one start the first alternative
    // written — std::regex's ECMAScript order. onMatch( offset ) returns false to stop.
    template<typename OnOffset>
    void forEachPlanMatch( const char* p, std::size_t n, OnOffset&& onMatch ) const noexcept
    {
        const std::string& only = plan.alternatives[ 0 ];
        if( plan.isAnchoredBegin || plan.isAnchoredEnd )
        {
            const std::size_t m      = only.size();
            const bool        fits   = ( plan.isAnchoredBegin && plan.isAnchoredEnd ) ? n == m : m <= n;
            const std::size_t offset = plan.isAnchoredBegin ? 0 : n - std::min( n, m );
            if( fits && std::memcmp( p + offset, only.data(), m ) == 0 )
            {
                onMatch( offset );
            }
            return;
        }
        for( std::size_t k = 0; k < n; )
        {
            const std::size_t at = k + ( plan.alternatives.size() == 1 ? regexFindLiteral( p + k, n - k, only )
                                                                       : strkern::findByteset( p + k, n - k, planHeads ) );
            if( at >= n )
            {
                return;
            }
            const auto chosen = std::find_if( plan.alternatives.begin(), plan.alternatives.end(), [ & ]( const std::string& a )
                                              { return a.size() <= n - at && std::memcmp( p + at, a.data(), a.size() ) == 0; } );
            if( chosen == plan.alternatives.end() )
            {
                k = at + 1;
                continue;
            }
            if( !onMatch( at ) )
            {
                return;
            }
            k = at + chosen->size();
        }
    }
};

// The line loop behind GuardedRegex::forEachLineMatch. The engine may throw here; the member holds the boundary, and
// `scan` keeps what was counted before a throw.
template<typename OnMatch>
void regexScanLines( const std::regex& engine, const RegexLiteralPaths& paths, std::string_view text, RegexLinePolicy policy,
                     OnMatch& onMatch, RegexLineScan& scan )
{
    const char*   base      = text.data();
    bool          isStopped = false;
    std::uint32_t line      = 1;
    const auto    report    = [ & ]( std::size_t byteOffset )
    {
        scan.verdict = RegexVerdict::Hit;
        isStopped    = !onMatch( line, byteOffset );
        return !isStopped;
    };
    const bool hasPlan = policy.useLiteralPaths && paths.hasPlan();
    if( hasPlan && paths.plan.isLineFree )
    {
        std::size_t counted = 0;
        paths.forEachPlanMatch( base, text.size(), [ & ]( std::size_t at )
        {
            line   += std::uint32_t( std::count( base + counted, base + at, '\n' ) );
            counted = at;
            return report( at );
        } );
        return;
    }
    const bool canJump   = policy.useLiteralPaths && !hasPlan && paths.required.isLineFree;
    const bool canFilter = policy.useLiteralPaths && !hasPlan && !paths.required.anyOf.empty();
    std::size_t lineBegin = 0;
    while( !isStopped )
    {
        if( canJump )
        {
            const std::size_t found = lineBegin + paths.findRequired( base + lineBegin, text.size() - lineBegin );
            if( found >= text.size() )
            {
                return;                                                  // no line past here can match
            }
            const std::size_t lastBreak = found == 0 ? std::string_view::npos : text.rfind( '\n', found - 1 );
            const std::size_t landing   = ( lastBreak == std::string_view::npos || lastBreak < lineBegin ) ? lineBegin : lastBreak + 1;
            line     += std::uint32_t( std::count( base + lineBegin, base + landing, '\n' ) );
            lineBegin = landing;
        }
        const std::size_t nl       = text.find( '\n', lineBegin );
        std::size_t       matchEnd = ( nl == std::string_view::npos ) ? text.size() : nl;
        matchEnd -= ( matchEnd > lineBegin && text[ matchEnd - 1 ] == '\r' ) ? 1 : 0;
        const std::size_t lineBytes = matchEnd - lineBegin;
        const bool        isCandidate = !hasPlan && ( canJump || !canFilter || paths.holdsRequired( base + lineBegin, lineBytes ) );
        if( hasPlan )
        {
            paths.forEachPlanMatch( base + lineBegin, lineBytes, [ & ]( std::size_t offset ) { return report( lineBegin + offset ); } );
        }
        else if( isCandidate && lineBytes > policy.engineLineBytesMax )
        {
            ++scan.skippedLineCount;
        }
        else if( isCandidate )
        {
            for( auto it = std::cregex_iterator( base + lineBegin, base + matchEnd, engine ); it != std::cregex_iterator(); ++it )
            {
                if( !report( lineBegin + std::size_t( it->position() ) ) )
                {
                    break;
                }
            }
        }
        if( nl == std::string_view::npos || nl + 1 >= text.size() )
        {
            return;                                                      // last line, or the newline that ended it was the final byte
        }
        lineBegin = nl + 1;
        ++line;
    }
}

inline constexpr unsigned kRegexFaultStackShift = 22;   // RIPWIRE_FAULT_REGEX_LINE_BOUND=1: the engine line bound is stack >> 22 (64 B at 256 MiB)

// FAULT INJECTION, because the only real trigger is one standard library's budget and the other has none:
// RIPWIRE_FAULT_REGEX_MATCH=1 makes every guarded match throw regex_error(error_complexity) inside its own try,
// so every entry point's Exhausted path is reachable on every platform. Non-NDEBUG only (rw::faultSwitchOn is
// `constexpr false` under NDEBUG, and the static is then a constant — no guard, no getenv, no branch in
// release), read ONCE per process (determinism), exact "1" (the rule faultSwitchOn owns). Called ONLY inside
// the try of a noexcept GuardedRegex member, so the throw it raises never leaves the seam — and before any literal
// path, so a pattern the engine never sees still reaches it.
// (Its former per-subject sibling RIPWIRE_FAULT_REGEX_MATCH_MIXED rode with the guard's per-file match budget —
// it existed only so one run could carry both causes of a stopped scan — and was removed with the budget, PR #397.)
inline void throwIfMatchFaultInjected()
{
    static const bool isEverySubject = rw::faultSwitchOn( "RIPWIRE_FAULT_REGEX_MATCH" );
    if( isEverySubject )
    {
        throw std::regex_error( std::regex_constants::error_complexity );
    }
}

// A compiled user pattern. Default-constructed it is an EMPTY slot (a member waiting to be filled); only
// compileGuardedRegex fills one, which is what keeps the screen in front of every engine that can be reached.
class GuardedRegex
{
public:
    GuardedRegex() = default;

    // Whether `subject` holds a match. A literal plan, or a Miss from the required-literals prefilter, never
    // reaches the engine and so is never too long. `stackBytes` (default SIZE_MAX: every pre-existing caller is
    // untouched) bounds only the branch that does — see maxEngineSubjectBytes and the file header above.
    RegexVerdict search( std::string_view subject, std::size_t stackBytes = SIZE_MAX ) const noexcept
    {
        try
        {
            throwIfMatchFaultInjected();
            if( paths.hasPlan() )
            {
                return paths.findsPlanMatch( subject.data(), subject.size() ) ? RegexVerdict::Hit : RegexVerdict::Miss;
            }
            return !paths.holdsRequired( subject.data(), subject.size() )                ? RegexVerdict::Miss
                 : subject.size() > maxEngineSubjectBytes( stackBytes )                   ? RegexVerdict::Skipped
                 : std::regex_search( subject.data(), subject.data() + subject.size(), engine ) ? RegexVerdict::Hit : RegexVerdict::Miss;
        }
        catch( const std::regex_error& ) { return RegexVerdict::Exhausted; }   // error_complexity / error_stack
        catch( const std::bad_alloc& )   { return RegexVerdict::Exhausted; }   // the matcher's state stack outgrew memory
    }

    // `captures` index into `subject`'s bytes, so the subject must outlive every read of them. No literal-plan fast
    // path here (a Hit must fill `captures`, which only the engine does), but the required-literals prefilter still
    // answers a Miss without the engine: a subject missing a literal every match needs has no match, and a Miss fills
    // nothing. Only a subject that could match meets `stackBytes`' bound — so a long line without the pattern's
    // literals is a decided Miss, not a Skip (CI on #283: every long skill line was skipped on libstdc++).
    RegexVerdict search( std::string_view subject, RegexCaptures& captures, std::size_t stackBytes = SIZE_MAX ) const noexcept
    {
        try
        {
            throwIfMatchFaultInjected();
            return !paths.holdsRequired( subject.data(), subject.size() )                          ? RegexVerdict::Miss
                 : subject.size() > maxEngineSubjectBytes( stackBytes )                           ? RegexVerdict::Skipped
                 : std::regex_search( subject.data(), subject.data() + subject.size(), captures, engine ) ? RegexVerdict::Hit : RegexVerdict::Miss;
        }
        catch( const std::regex_error& ) { return RegexVerdict::Exhausted; }
        catch( const std::bad_alloc& )   { return RegexVerdict::Exhausted; }
    }

    // Every non-overlapping match in `text` read ONE LINE AT A TIME, in order: onMatch( line, byteOffset ) with a 1-based
    // line and the match's offset in `text`, returning false to stop. A line is the bytes before its '\n' less one
    // trailing '\r'; a trailing '\n' ends the last line rather than starting an empty one, and empty text has no lines
    // (src/search.h's grepScanText says why grep reads lines). Exhausted means the matches reported before the engine
    // gave up are the ones known, and no more; onMatch runs inside the boundary and must throw nothing but bad_alloc.
    //
    // The literal paths, in order: a literal plan with no line break in any alternative scans the whole text once; any
    // other plan answers each line itself; required literals holding no line break jump from occurrence to occurrence
    // and hand only those lines on; folded ones are checked per line. What is left goes to the engine — unless the line
    // is longer than `policy.engineLineBytesMax`, and then it is skipped and counted.
    template<typename OnMatch>
    RegexLineScan forEachLineMatch( std::string_view text, RegexLinePolicy policy, OnMatch&& onMatch ) const noexcept
    {
        RegexLineScan scan;
        if( text.empty() )
        {
            return scan;                                                 // no lines, so nothing to match (and nothing to fault)
        }
        try
        {
            throwIfMatchFaultInjected();
            regexScanLines( engine, paths, text, policy, onMatch, scan );
        }
        catch( const std::regex_error& ) { scan.verdict = RegexVerdict::Exhausted; }
        catch( const std::bad_alloc& )   { scan.verdict = RegexVerdict::Exhausted; }
        return scan;
    }

    // regexMaxSubjectBytes for this pattern. The non-NDEBUG fault switch RIPWIRE_FAULT_REGEX_LINE_BOUND=1 caps it at
    // stackBytes >> kRegexFaultStackShift on every library (64 B on a 256 MiB stack, and proportionally less on a smaller
    // one), so the skip path, its disclosure and its dependence on the stack are reachable where the engine never needs them.
    std::size_t maxEngineSubjectBytes( std::size_t stackBytes ) const noexcept
    {
        static const bool isCapped = rw::faultSwitchOn( "RIPWIRE_FAULT_REGEX_LINE_BOUND" );
        return isCapped ? std::min( regexMaxSubjectBytes( cost, stackBytes ), stackBytes >> kRegexFaultStackShift ) : regexMaxSubjectBytes( cost, stackBytes );
    }

private:
    friend RegexCompile compileGuardedRegex( const std::string& pattern, RegexSyntax syntax ) noexcept;

    std::regex         engine;
    RegexLiteralPaths  paths;
    RegexRecursionCost cost;
};

struct RegexCompile
{
    GuardedRegex               regex;                // an empty slot whenever `refusal` is set — never matched
    std::optional<std::string> refusal;              // the named reason, in the words --regex has always printed
    bool                       isScreened = false;   // true ⇒ a structural screen refused it; false ⇒ the engine's parser did

    // F-H9 (CodeRabbit on #277): true only when the ENGINE'S OWN parser refused with error_badbrace — a
    // syntactically well-formed {min,max} whose bound ORDER is wrong for the digits THIS pattern happened to
    // hold (e.g. "9" substituted for a backreference where the template needed \1 >= 10). That is a fact about
    // which digits landed there, never about the pattern's structure, so a caller building a template from a
    // placeholder (arch.h's TO-template parse-time probe) can treat this refusal as "maybe valid for a
    // DIFFERENT value" rather than "invalid for every value" — every other refusal (a screen refusal, or any
    // other engine error) still means the same thing for any value that could ever be substituted.
    bool                       isIntervalRangeOnly = false;
};

// Screen, then compile. The screen's verdict is platform-independent, so it decides first; only a pattern it
// passes is handed to the engine's parser, whose diagnostic is returned verbatim — or, when the parser ran out
// of memory (a huge bracket expression or repeat count), a fixed sentence saying so. The value carries the
// verdict; nothing is thrown past this function. A compiled pattern also carries its shape (the literal plan,
// the required literals, the recursion cost), read here once.
inline RegexCompile compileGuardedRegex( const std::string& pattern, RegexSyntax syntax ) noexcept
{
    RegexCompile out;
    out.refusal = screenRegexPattern( pattern );
    if( out.refusal )
    {
        out.isScreened = true;
        return out;
    }
    try                                { out.regex.engine.assign( pattern, syntax ); }
    catch( const std::regex_error& e )
    {
        out.refusal             = std::string( e.what() );
        out.isIntervalRangeOnly = e.code() == std::regex_constants::error_badbrace;
        return out;
    }
    catch( const std::bad_alloc& )     { out.refusal = std::string( "invalid regular expression: the engine ran out of memory compiling it" ); return out; }
    out.regex.paths.plan     = regexLiteralPlanOf( pattern, syntax );
    out.regex.paths.required = regexRequiredLiteralsOf( pattern, syntax );
    out.regex.cost           = regexRecursionCostOf( pattern );
    for( const std::string& alternative : out.regex.paths.plan.alternatives )
    {
        out.regex.paths.planHeads.add( static_cast<unsigned char>( alternative[ 0 ] ) );
    }
    return out;
}

// The boundary, held by the compiler rather than by this comment: every entry point a call site can reach is
// noexcept, so a future edit that lets an engine exception escape the seam fails to build instead of shipping.
static_assert( noexcept( compileGuardedRegex( std::declval<const std::string&>(), kRegexEcmaScript ) ) );
static_assert( noexcept( std::declval<const GuardedRegex&>().search( std::string_view() ) ) );
static_assert( noexcept( std::declval<const GuardedRegex&>().search( std::string_view(), std::declval<RegexCaptures&>() ) ) );
static_assert( noexcept( std::declval<const GuardedRegex&>().forEachLineMatch( std::string_view(), RegexLinePolicy{},
                                                                              []( std::uint32_t, std::size_t ) { return true; } ) ) );

}   // namespace rw
