#pragma once

// redact.h — Wave 4 #7: deterministic secret redaction of EMITTED context (Repomix / octocode table
// stakes). ripwire maps get pasted into cloud LLMs, so any credential that lives in a source body / doc
// must not leave the machine verbatim. Applied ONLY at the BODY-EMISSION seams (CDATA source in
// packSource/packBodies/packOutline, doc bodies in recall.h, extracted docText) — NEVER to symbol
// names / signatures in the default map (identifiers are not secrets, and the default map must stay
// byte-stable).
//
// PRECISION OVER RECALL is the design rule: a FALSE redaction of real source code is worse than a miss
// (it silently corrupts the context the agent reasons over), so every pattern is a tight, high-confidence
// credential SHAPE. The generic "long hex/base64" catch-all fires ONLY on a line that ALSO names a
// credential assignment (api_key/secret/token/password …), so a 40-char git SHA in prose or a base64
// test vector without keyword context is left intact.
//
// Determinism: pure function of the input bytes. std::regex objects are compiled ONCE (function-local
// statics) and reused; the same bytes redact to the same bytes on every run, warm or cold, so the
// det-gate and warm==cold both hold with redaction active.
//
// Replacement is length-independent: a stable short PREFIX of the original match + a fixed marker, e.g.
//   AKIAIOSFODNN7EXAMPLE  ->  AKIA…[REDACTED:aws-key]
// so the map stays readable ("there was an AWS key here") without leaking the secret, and the output size
// does not depend on the secret's length (deterministic byte count per redaction kind).
//
// Style: Allman braces; spaces inside parens; VERIFY/degrade; declarative pattern TABLE, not a switch.

#include "infra/Diagnostics.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <regex>
#include <span>
#include <string>
#include <string_view>

namespace rw
{

// ── the redaction kinds (one counter slot each) ──────────────────────────────────────────────────────
enum class SecretKind : std::uint8_t
{
    AwsKeyId,        // AKIA… access-key id
    AwsSecret,       // 40-char base64-ish assigned to a secret/aws-named field
    GitHubToken,     // ghp_/gho_/ghs_/github_pat_…
    SlackToken,      // xox[baprs]-…
    GoogleApiKey,    // AIza…
    OpenAiKey,       // sk-… / sk-ant-… (OpenAI / Anthropic)
    PrivateKeyBlock, // -----BEGIN … PRIVATE KEY-----
    GenericAssigned, // long hex/base64 ON a line that also names api_key/secret/token/password
    JwtToken,        // eyJ… three-segment (header.payload.signature) JSON Web Token — self-anchored, no keyword gate needed
    kCount
};

// Per-run tally, one slot per SecretKind. main.cpp owns ONE of these for the whole invocation and passes
// it (by pointer) into every body-emission seam, so the single end-of-run stderr summary aggregates every
// seam's redactions. A null pointer at a seam == redaction DISABLED there (--no-redact).
struct RedactCounts
{
    std::array<std::uint32_t, std::size_t( SecretKind::kCount )> byKind{};   // value-initialised → all 0

    std::uint32_t total() const noexcept
    {
        std::uint32_t t = 0;
        for( std::uint32_t v : byKind )
        {
            t += v;
        }
        return t;
    }

    void bump( SecretKind k ) noexcept { ++byKind[ std::size_t( k ) ]; }
};

// ── the declarative pattern table ────────────────────────────────────────────────────────────────────
//
// Each row: the credential SHAPE (an ECMAScript regex), the kind it maps to, the marker text spliced in,
// and how many leading chars of the match to KEEP as a human-readable hint. The rationale for the
// tightness of each pattern is documented inline — this is where "precision over recall" is enforced.
struct RedactRule
{
    const char* pattern;    // ECMAScript regex; compiled ONCE into a static std::regex (see redactSecrets)
    SecretKind  kind;
    const char* marker;     // fixed replacement tail, e.g. "[REDACTED:aws-key]"
    std::size_t keepPrefix; // how many leading bytes of the match to keep before "…<marker>"
};

// The table order is the MATCH-PRIORITY order (first rule that matches a span wins that span). More
// specific vendor shapes come before the generic keyword-gated catch-all so a GitHub token is labelled
// "github-token", not "secret". Every regex is deliberately ANCHORED to a distinctive literal prefix (or,
// for the generic rule, gated by a keyword on the same line) so it cannot fire on ordinary identifiers.
inline constexpr std::array<RedactRule, 10> kRedactRules = {{
    // AWS access-key id — the "AKIA" prefix + exactly 16 upper-alnum chars is an AWS-defined, fixed shape
    // that does not occur in normal prose/code (20 chars total, all [A-Z0-9]). Very low false-positive risk.
    { R"(AKIA[0-9A-Z]{16})", SecretKind::AwsKeyId, "[REDACTED:aws-key]", 4 },

    // Private-key PEM header — the literal "-----BEGIN … PRIVATE KEY-----" banner is unambiguous; if it is
    // in an emitted body the whole key block follows. We redact the header line (a visible, deterministic
    // marker); the base64 body that follows is separately caught by GenericAssigned only if keyword-gated,
    // but the header alone is the high-signal tell that a key is present. Zero false positives.
    { R"(-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----)", SecretKind::PrivateKeyBlock, "[REDACTED:private-key]", 11 },

    // GitHub tokens — the ghp_/gho_/ghs_/ghu_/ghr_ (fine-grained + classic) and github_pat_ prefixes are
    // GitHub-assigned and never appear as ordinary identifiers; require ≥20 following token chars so a bare
    // "ghp_" mention in prose is not hit. Distinct marker so the source of the leak is obvious.
    { R"(gh[posur]_[A-Za-z0-9_]{20,})",       SecretKind::GitHubToken, "[REDACTED:github-token]", 4 },
    { R"(github_pat_[A-Za-z0-9_]{20,})",       SecretKind::GitHubToken, "[REDACTED:github-token]", 11 },

    // Slack tokens — xox[b|a|p|r|s]- bot/app/user/refresh/… prefix; the "xox?-" shape is Slack-specific.
    // Require ≥10 body chars after the dash so "xoxb-" mentioned in docs is not redacted.
    { R"(xox[baprs]-[A-Za-z0-9-]{10,})",       SecretKind::SlackToken, "[REDACTED:slack-token]", 5 },

    // Google API key — "AIza" + exactly 35 of [A-Za-z0-9_-] is Google's fixed 39-char key shape. The AIza
    // prefix + exact length makes accidental matches essentially impossible.
    { R"(AIza[0-9A-Za-z_\-]{35})",             SecretKind::GoogleApiKey, "[REDACTED:google-api-key]", 4 },

    // Anthropic keys FIRST (sk-ant-…), then OpenAI (sk-…): the sk-ant- prefix is a strict subset of sk-, so
    // it must be tried before the shorter rule to earn the more specific label. Both require ≥20 body chars.
    // The sk- prefix + a long [A-Za-z0-9_-] run is the OpenAI/Anthropic key shape; a short "sk-foo"
    // identifier (below the 20-char threshold) is intentionally NOT matched — that is the decoy the gate asserts.
    { R"(sk-ant-[A-Za-z0-9_\-]{20,})",          SecretKind::OpenAiKey, "[REDACTED:anthropic-key]", 7 },
    { R"(sk-[A-Za-z0-9_\-]{20,})",              SecretKind::OpenAiKey, "[REDACTED:openai-key]", 3 },

    // JWT — eyJ (base64 of '{"') is the distinctive, self-anchoring JWT header-start, as distinctive as AKIA:
    // real JSON headers ({"alg":... / {"typ":...) base64-encode to an "eyJ" prefix essentially always. A JWT
    // is three base64url runs joined by '.' (header.payload.signature); requiring all three segments (with a
    // minimum length on each) keeps this self-anchored — NO keyword gate needed, same tier as GitHub/Slack/
    // Google tokens above. This is what catches "Authorization: Bearer eyJ…" even though "auth" alone (a
    // substring of "authorization") fails the GenericAssigned keyword gate below (A4-F11) — the JWT rule
    // doesn't need that gate at all, it recognizes the shape directly. Placed BEFORE GenericAssigned so the
    // whole three-segment token gets ONE distinct "jwt" label instead of being chewed into per-segment
    // [REDACTED:secret] hits (only when/if the line also happened to be keyword-gated).
    { R"(eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,})", SecretKind::JwtToken, "[REDACTED:jwt]", 6 },

    // Generic long hex/base64 credential — the LOW-precision shape, so it is GATED: it only redacts a
    // ≥32-char [A-Za-z0-9+/=_-] run when the SAME line ALSO contains an assignment to a credential-named
    // field (api_key / secret / token / password, case-insensitive, followed by : or =). This is what keeps
    // a 40-char git SHA in prose or a lone base64 test vector INTACT — without the keyword on the line the
    // rule never fires. The keyword gate is applied per-line in redactSecrets (see below), not in this regex.
    { R"([A-Za-z0-9+/=_\-]{32,})",              SecretKind::GenericAssigned, "[REDACTED:secret]", 4 },
}};

namespace redactdetail
{

// The per-line keyword gate for the GenericAssigned rule: does this line assign a credential-named field?
// (?i)(api[_-]?key|secret|token|password|passwd|pwd|apikey)\s*[:=]. Hand-rolled (no regex) so it is cheap
// and can run per candidate line. Case-insensitive substring scan for one of the keywords immediately
// followed (allowing spaces) by ':' or '='.
inline bool lineNamesCredential( std::string_view line ) noexcept
{
    // "loose" keywords (A4-F11): "authorization"/"bearer" name a credential even without a ':'/'=' — an HTTP
    // header line reads "Authorization: Bearer <token>" (':' after "authorization" — already covered by the
    // strict rule below) but the *value* itself just reads "Bearer <token>" with nothing but whitespace
    // between keyword and token (no assignment punctuation at all). Kept as a SEPARATE, short list (not
    // folded into kKeywords) so this looser whitespace-then-token match cannot silently widen precision for
    // the other, punctuation-anchored keywords (api_key/secret/token/… stay ':'/'=' only — the "auth" entry
    // below also stays strict, since it's a deliberately short generic prefix).
    static constexpr std::string_view kLooseKeywords[] = { "authorization", "bearer" };
    static constexpr std::string_view kKeywords[] = {
        "api_key", "api-key", "apikey", "secret", "token", "password", "passwd", "pwd", "access_key", "auth"
    };
    const auto lower = []( char c ) noexcept -> char
    { return ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c; };
    const auto caseEq = [ & ]( std::string_view line_, std::size_t i, std::string_view kw ) noexcept -> bool
    {
        if( i + kw.size() > line_.size() )
        {
            return false;
        }
        for( std::size_t j = 0; j < kw.size(); ++j )
        {
            if( lower( line_[i + j] ) != kw[j] )
            {
                return false;
            }
        }
        return true;
    };

    for( std::string_view kw : kLooseKeywords )
    {
        if( line.size() < kw.size() )
        {
            continue;
        }
        for( std::size_t i = 0; i + kw.size() <= line.size(); ++i )
        {
            if( !caseEq( line, i, kw ) )
            {
                continue;
            }

            // after the keyword: ':'/'=' (possibly through spaces) counts, same as the strict rule; OR at
            // least one space/tab followed by more content on the line (the bare "Bearer <token>" shape).
            std::size_t p = i + kw.size();
            std::size_t q = p;
            while( q < line.size() && ( line[q] == ' ' || line[q] == '\t' ) )
            {
                ++q;
            }
            if( q < line.size() && ( line[q] == ':' || line[q] == '=' ) )
            {
                return true;
            }
            if( q > p && q < line.size() )
            {
                return true; // whitespace-then-token
            }
        }
    }

    for( std::string_view kw : kKeywords )
    {
        // scan for a case-insensitive occurrence of kw
        if( line.size() < kw.size() )
        {
            continue;
        }
        for( std::size_t i = 0; i + kw.size() <= line.size(); ++i )
        {
            if( !caseEq( line, i, kw ) )
            {
                continue;
            }

            // after the keyword, allow spaces/tabs, then require ':' or '=' (the assignment tell)
            std::size_t p = i + kw.size();
            while( p < line.size() && ( line[p] == ' ' || line[p] == '\t' ) )
            {
                ++p;
            }
            if( p < line.size() && ( line[p] == ':' || line[p] == '=' ) )
            {
                return true;
            }
        }
    }
    return false;
}

// The line [lineStart, lineEnd) of `s` that contains byte offset `pos` — used to apply the GenericAssigned
// keyword gate to the enclosing line of a candidate match.
inline std::string_view enclosingLine( std::string_view s, std::size_t pos ) noexcept
{
    std::size_t a = pos;
    while( a > 0 && s[a - 1] != '\n' )
    {
        --a;
    }
    std::size_t b = pos;
    while( b < s.size() && s[b] != '\n' )
    {
        ++b;
    }
    return s.substr( a, b - a );
}

// ── first-byte dispatch table (perf) ─────────────────────────────────────────────────────────────────
// redactSecrets's sweep used to try every one of kRedactRules.size() (10) regex_search(match_continuous)
// calls at EVERY byte position of the input, even though each rule's SHAPE is anchored to a small, fixed
// set of possible first bytes (a literal prefix, or — for the one unprefixed rule — its leading character
// class). Precompute, ONCE, a 256-entry bitmask (bit r set ⇒ kRedactRules[r] can possibly start a match at
// a byte with this value) so the sweep only attempts the rules whose first-byte set contains bytes[i].
// This changes ZERO redaction results: a regex that requires literal prefix "AKIA" cannot match_continuous
// at a byte that isn't 'A', so skipping it there was always a guaranteed non-match, never a skipped hit.
// The GenericAssigned rule's leading character class — [A-Za-z0-9+/=_\-] — as a membership table. ONE
// definition, read by both consumers: the first-byte dispatch below (that rule has no literal prefix, so
// its first-byte set IS this class) and redactSecrets's run scan. Spelling it twice is how the two would
// silently drift apart, and a drift there is a redaction that stops firing.
inline std::array<bool, 256> buildGenericClassTable() noexcept
{
    std::array<bool, 256> cls{};
    for( unsigned char c = 'A'; c <= 'Z'; ++c )
    {
        cls[c] = true;
    }
    for( unsigned char c = 'a'; c <= 'z'; ++c )
    {
        cls[c] = true;
    }
    for( unsigned char c = '0'; c <= '9'; ++c )
    {
        cls[c] = true;
    }
    for( unsigned char c : { '+', '/', '=', '_', '-' } )
    {
        cls[c] = true;
    }
    return cls;
}

// The minimum run length that rule's pattern requires — the "{32,}" in [A-Za-z0-9+/=_\-]{32,}.
inline constexpr std::size_t kGenericMinRunLength = 32;

inline std::array<std::uint16_t, 256> buildFirstByteRuleMask() noexcept
{
    std::array<std::uint16_t, 256> mask{};   // value-initialised → all-zero (no rule can start here)

    const auto addRule = [ & ]( std::size_t ruleIndex, std::initializer_list<unsigned char> bytes )
    {
        for( unsigned char b : bytes )
        {
            mask[b] = std::uint16_t( mask[b] | std::uint16_t( 1u << ruleIndex ) );
        }
    };

    // rule 0: AKIA[0-9A-Z]{16}                        — literal prefix "AKIA" → 'A'
    addRule( 0, { 'A' } );
    // rule 1: -----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----  — literal prefix "-----BEGIN…" → '-'
    addRule( 1, { '-' } );
    // rule 2: gh[posur]_[A-Za-z0-9_]{20,}              — literal prefix "gh" → 'g'
    addRule( 2, { 'g' } );
    // rule 3: github_pat_[A-Za-z0-9_]{20,}             — literal prefix "github_pat_" → 'g'
    addRule( 3, { 'g' } );
    // rule 4: xox[baprs]-[A-Za-z0-9-]{10,}             — literal prefix "xox" → 'x'
    addRule( 4, { 'x' } );
    // rule 5: AIza[0-9A-Za-z_\-]{35}                   — literal prefix "AIza" → 'A'
    addRule( 5, { 'A' } );
    // rule 6: sk-ant-[A-Za-z0-9_\-]{20,}               — literal prefix "sk-ant-" → 's'
    addRule( 6, { 's' } );
    // rule 7: sk-[A-Za-z0-9_\-]{20,}                   — literal prefix "sk-" → 's'
    addRule( 7, { 's' } );
    // rule 8: eyJ[...]\.[...]\.[...]                    — literal prefix "eyJ" → 'e'
    addRule( 8, { 'e' } );
    // rule 9 (GenericAssigned): [A-Za-z0-9+/=_\-]{32,} — NO fixed literal prefix; a match can start at any
    // byte in the character class itself, so its first-byte set IS that class, read from its one definition.
    const std::array<bool, 256> genericClass = buildGenericClassTable();
    for( std::size_t b = 0; b < genericClass.size(); ++b )
    {
        if( genericClass[b] )
        {
            addRule( 9, { static_cast<unsigned char>( b ) } );
        }
    }

    return mask;
}

// ── per-line and per-run memoization (perf) ──────────────────────────────────────────────────────────
// Three of the sweep's costs were O(lineLength) or O(runLength) *at every candidate position*, i.e. O(n²)
// on a file whose "lines" are hundreds of kilobytes — a minified or vendored bundle such as
// .yarn/releases/*.cjs, which arrives here WHOLE through --expand's whole-file candidate. Measured on
// babel__babel-13928's 2.1 MB / 768-line yarn bundle, one --expand selector took >20 minutes, ~100% of it
// inside redactSecrets: enclosingLine walked to both line boundaries, lineNamesCredential rescanned the
// whole line for its keyword, and the GenericAssigned regex re-consumed the whole class run — none of
// which depend on WHERE in the line or run the cursor sits. The two types below hold each of those values
// for exactly as long as it stays true. Pure memoization: same matches, same gate verdicts, same output
// bytes (verified byte-identical on 17 corpora), with the boundary cases pinned by redactfixcheck.sh.

// LineGate — the GenericAssigned keyword gate, resolved once per LINE instead of once per candidate
// position. Both halves of that verdict (which line the cursor is in, and whether that line names a
// credential) are functions of the LINE, so a cursor that has not left the line reuses both. The cached
// range is CLOSED — [lineStart, lineEnd] — because that is exactly the set of offsets enclosingLine maps
// to one line: lineEnd indexes the terminating '\n' (or the end of input on the last line), and
// enclosingLine( s, thatNewline ) returns the line before it. Initialised empty (start > end) so the
// first query always computes.
struct LineGate
{
    std::size_t lineStart       = 1;
    std::size_t lineEnd         = 0;
    bool        namesCredential = false;

    bool query( std::string_view in, std::size_t pos ) noexcept
    {
        if( pos < lineStart || pos > lineEnd )
        {
            const std::string_view line = enclosingLine( in, pos );
            lineStart                   = std::size_t( line.data() - in.data() );
            lineEnd                     = lineStart + line.size();
            namesCredential             = lineNamesCredential( line );
        }
        return namesCredential;
    }
};

// ClassRun — the maximal GenericAssigned character-class run containing the cursor, found once per RUN.
// That rule's pattern is one greedy class run with nothing after it, so regex_search( match_continuous )
// at a cursor always consumes the maximal run FROM that cursor — an O(runLength) call at every position
// inside the run. The run's END is the same for every position inside it, so it is scanned once and the
// match reduces to subtraction. [runStart, runEnd) is half-open; initialised empty (start > end).
struct ClassRun
{
    std::size_t runStart = 1;
    std::size_t runEnd   = 0;

    // The rule's match length at `pos` — the maximal class run from `pos` — or 0 where it cannot match.
    // Exactly equivalent to regex_search( match_continuous ) on the pattern, minimum length aside.
    std::size_t matchLengthAt( std::string_view in, std::size_t pos, const std::array<bool, 256>& cls ) noexcept
    {
        if( !cls[ static_cast<unsigned char>( in[pos] ) ] )
        {
            return 0;
        }
        if( pos < runStart || pos >= runEnd )
        {
            runStart = pos;
            runEnd   = pos;
            while( runEnd < in.size() && cls[ static_cast<unsigned char>( in[runEnd] ) ] )
            {
                ++runEnd;
            }
        }
        return runEnd - pos;
    }
};

// SweepState — the memo caches one redactSecrets sweep carries. Both are keyed on a span the cursor stays
// inside and the cursor only ever advances, so a stale hit is impossible; they live for one call and are
// never shared between calls (the transform must stay a pure function of its input).
struct SweepState
{
    LineGate gate;
    ClassRun run;
};

// The length of rule `ruleIndex`'s match starting EXACTLY at `pos`, or 0 if that rule does not match
// there. One contract, two answering paths:
//
//   • GenericAssigned — answered structurally, never by the regex. Its pattern is a bare greedy class run
//     ([A-Za-z0-9+/=_\-]{32,}), so a regex anchored at the cursor re-consumes the entire run at EVERY
//     position inside it; ClassRun finds that run's end once instead. It is also the one GATED rule: a
//     run only counts as a secret when its line names a credential assignment (LineGate), which is what
//     keeps a git SHA or a base64 test vector in prose whole. A declined gate reads as "no match", which
//     is exactly what it was before — the byte then takes the verbatim-copy path.
//   • every other rule — regex_search anchored with match_continuous. They are all self-anchoring on a
//     distinctive literal prefix, so they fail within a byte or two and need no structural shortcut.
inline std::size_t matchLengthAtCursor( std::size_t ruleIndex, std::string_view in, std::size_t pos,
                                        std::span<const std::regex> compiled, SweepState& state )
{
    // the GenericAssigned class table — built once, and the same table buildFirstByteRuleMask read.
    static const std::array<bool, 256> kGenericClass = buildGenericClassTable();

    if( kRedactRules[ruleIndex].kind == SecretKind::GenericAssigned )
    {
        const std::size_t runLength = state.run.matchLengthAt( in, pos, kGenericClass );
        if( runLength < kGenericMinRunLength )
        {
            return 0;   // shorter than the pattern's minimum → no match at this cursor
        }
        return state.gate.query( in, pos ) ? runLength : 0;
    }

    std::cmatch m;
    // match_continuous: the regex must match STARTING AT the cursor (not later in the string), so the sweep
    // advances one candidate position at a time and rule priority (table order) is honoured.
    if( !std::regex_search( in.data() + pos, in.data() + in.size(), m, compiled[ruleIndex],
                            std::regex_constants::match_continuous ) )
    {
        return 0;
    }
    return std::size_t( m.length( 0 ) );
}

}   // namespace redactdetail

// redactSecrets — scan `in` for credential shapes; write the redacted text to `out`; bump `counts` per
// redaction. Returns true iff at least one redaction was made. Pure function of `in`: the regexes are
// compiled ONCE (function-local statics) so the transform is deterministic run-to-run (det-gate + warm==cold).
//
// Algorithm: a single left-to-right sweep. At each position we try the rules the first-byte mask says can
// start here (table order = priority) anchored at the cursor with match_continuous; the first that matches
// wins. The GenericAssigned rule is answered by ClassRun rather than by the regex, and additionally
// requires its enclosing line to name a credential (LineGate), else it is skipped so ordinary long tokens
// are preserved. A match is replaced by keepPrefix bytes of the original + "…" + the marker; non-matching
// bytes are copied verbatim.
//
// This is O(n · rules) — LINEAR in the input, which it only became once the two caches landed. Before them
// the line gate and the class-run match were each re-derived at every position, so the sweep was quadratic
// in LINE length; that is invisible on source and fatal on a minified bundle, where a "line" is hundreds of
// kilobytes and --expand hands the whole file to this function.
inline bool redactSecrets( std::string_view in, std::string& out, RedactCounts& counts )
{
    // compile once — a static array of {regex, ruleIndex}. std::regex construction is not cheap, but it
    // happens exactly once per process; every call reuses the compiled objects (determinism + speed).
    static const std::array<std::regex, kRedactRules.size()> kCompiled = [] {
        std::array<std::regex, kRedactRules.size()> a{};
        for( std::size_t i = 0; i < kRedactRules.size(); ++i )
        {
            a[i] = std::regex( kRedactRules[i].pattern, std::regex::ECMAScript | std::regex::optimize );
        }
        return a;
    }();

    // first-byte dispatch mask (see buildFirstByteRuleMask) — also compiled/built exactly once.
    static const std::array<std::uint16_t, 256> kFirstByteMask = redactdetail::buildFirstByteRuleMask();
    static_assert( kRedactRules.size() <= 16, "kFirstByteMask bitmask is a uint16_t — widen if rules exceed 16" );

    out.clear();
    out.reserve( in.size() + 16 );

    bool        anyRedacted = false;
    const char* base        = in.data();
    std::size_t i           = 0;
    const std::size_t N     = in.size();

    redactdetail::SweepState state;   // the per-sweep memo caches (see SweepState)

    while( i < N )
    {
        bool matchedHere = false;

        // first-byte dispatch: only the rules whose first-byte set contains bytes[i] can possibly
        // match_continuous here (every rule's shape is anchored to a literal prefix or, for the one
        // unprefixed rule, its own leading character class) — skip the rest without ever calling regex_search.
        const std::uint16_t candidateRules = kFirstByteMask[ static_cast<unsigned char>( in[i] ) ];

        for( std::size_t r = 0; candidateRules != 0 && r < kRedactRules.size(); ++r )
        {
            if( !( candidateRules & std::uint16_t( 1u << r ) ) )
            {
                continue;
            }

            // 0 = this rule does not match at the cursor — no match, an empty match (zero progress is never
            // allowed), or the GenericAssigned gate declining a run whose line names no credential.
            const std::size_t len = redactdetail::matchLengthAtCursor( r, in, i, kCompiled, state );
            if( len == 0 )
            {
                continue;
            }

            const RedactRule& rule = kRedactRules[r];

            // splice: keepPrefix original bytes + "…" (U+2026, 3 UTF-8 bytes) + the fixed marker. Deterministic,
            // length-independent (the emitted bytes never depend on the secret's length beyond the kept prefix).
            const std::size_t keep = rule.keepPrefix < len ? rule.keepPrefix : len;
            out.append( base + i, keep );
            out.append( "\xE2\x80\xA6" );   // "…"
            out.append( rule.marker );

            counts.bump( rule.kind );
            anyRedacted = true;
            i          += len;             // skip the whole matched secret
            matchedHere = true;
            break;
        }

        if( !matchedHere )
        {
            out.push_back( in[i] );        // ordinary byte — copy verbatim
            ++i;
        }
    }

    return anyRedacted;
}

// Convenience seam helper: if `counts` is non-null (redaction enabled), redact `body` IN PLACE (only
// reassigning when something changed, to avoid a needless copy); if null (--no-redact), leave it untouched.
// Every body-emission seam calls this on its body text just before CDATA-encoding / writing.
inline void redactInPlace( std::string& body, RedactCounts* counts )
{
    if( counts == nullptr )
    {
        return; // --no-redact: pass source through verbatim
    }
    std::string redacted;
    if( redactSecrets( body, redacted, *counts ) )
    { // only swap when a secret was actually found
        body = std::move( redacted );
    }
}

// ── §B10.2: THE TALLY IS PER-DOCUMENT, NOT PER-SERIALIZATION ─────────────────────────────────────────────
// A redaction is a property of the CONTENT. An emitter that renders the same source text TWICE — once as XML
// and once as JSON, which is exactly what --pack-task --json does — finds every secret twice and, sharing one
// counter, charges every secret twice. MEASURED on a two-secret corpus: `--pack-task --json` claimed 4
// redactions while emitting 2 markers, JSON dialect only (`--for` reports the same number in both dialects
// because it renders once).
//
// Freeze the tally across the second rendering. Scoped and RAII rather than a snapshot/restore pair at the
// call site, for the reason this round keeps finding: a restore that a later edit forgets, or that an early
// `return` skips, silently reinstates the over-count — and it would look exactly like the bug it fixed.
//
// NOT "pass nullptr to the second serializer": nullptr is the --no-redact spelling, so the second dialect
// would emit RAW SECRETS. The emitters must keep redacting; they must not re-bill.
struct RedactTallyFreeze
{
    RedactCounts* m_counts;   // nullptr under --no-redact — then this is inert, and correctly so
    RedactCounts  m_atEntry;

    explicit RedactTallyFreeze( RedactCounts* counts ) noexcept
        : m_counts( counts ), m_atEntry( counts ? *counts : RedactCounts{} ) {}
    ~RedactTallyFreeze()
    {
        if( m_counts )
        {
            *m_counts = m_atEntry;
        }
    }

    RedactTallyFreeze( const RedactTallyFreeze& )            = delete;
    RedactTallyFreeze& operator=( const RedactTallyFreeze& ) = delete;
};

// Emit the single per-run stderr summary IF anything was redacted. Called once by main.cpp after all
// emission is done. Deterministic, count-by-kind, one line (plus the per-kind breakdown). No-op when nothing
// was redacted (so a clean map prints nothing extra).
inline void reportRedactions( std::FILE* err, const RedactCounts& counts )
{
    const std::uint32_t total = counts.total();
    if( total == 0 )
    {
        return;
    }

    // fixed kind→label table, iterated in enum order for a deterministic summary line
    static constexpr std::array<const char*, std::size_t( SecretKind::kCount )> kLabel = {
        "aws-key", "aws-secret", "github-token", "slack-token", "google-api-key",
        "openai/anthropic-key", "private-key", "keyword-gated-secret", "jwt"
    };

    std::fprintf( err, "ripwire: redacted %u secret%s from emitted context (",
                  total, total == 1 ? "" : "s" );
    bool first = true;
    for( std::size_t k = 0; k < std::size_t( SecretKind::kCount ); ++k )
    {
        if( counts.byKind[k] == 0 )
        {
            continue;
        }
        std::fprintf( err, "%s%s=%u", first ? "" : " ", kLabel[k], counts.byKind[k] );
        first = false;
    }
    std::fprintf( err, ") — pass --no-redact to disable\n" );
}

}   // namespace rw
