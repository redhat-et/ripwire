#pragma once

// arch.h — architectural fitness functions (layering rules) for --arch (RESEARCH_codeIntelligence §2).
// The rules are the USER's, declared in a small text file; ctxpack imposes no architecture of its own —
// it just enforces the one you declare against the #include graph and reports the crossing edges, with a
// non-zero exit code for CI. Instrument, not judge.
//
// THE PATH A RULE SEES IS ROOT-RELATIVE. Every matcher in this file — `layer` substrings and the ABS-4 regex
// path-rules — is handed `src/core/x.cpp`, not `/abs/where/you/cloned/src/core/x.cpp` and not `./src/…`. The
// caller (main.cpp's --arch block) does that normalization with relForHash, the same one the baseline hash
// uses, and the reason is that these are UNANCHORED matchers: a bare substring and a regex_search both bind
// to the leftmost hit anywhere in the string, so an absolute path silently offers them the directory names of
// the machine the tree happens to sit on. Write rules repo-relative; they then mean the same thing in every
// checkout, which is the only way `--arch` can be a CI gate.
//
// Rules file grammar (whitespace-tokenised, '#' starts a comment):
//   layer NAME = substr1 substr2 ...   a file is in NAME if its ROOT-RELATIVE path contains any substr
//                                       (first layer wins)
//   deny  FROM -> TO                   FROM-files may not #include TO-files   (FROM/TO = a layer name or '*')
//   allow FROM -> TO                   if a layer has ANY allow rule it becomes allow-listed:
//                                       only its allowed targets are permitted, everything else is a violation
//
// --baseline support (S5-B):
//   A sidecar file `.ctxpack_arch_baseline` in the CWD holds one FNV-1a-64 hex hash per line, each
//   identifying an accepted violation by stable key = src_file + NUL + dst_file + NUL + rule_label.
//   First run with --baseline writes the sidecar and exits 0 (accept the current debt).
//   Subsequent runs suppress baselined violations; exit 2 only on NEW (un-baselined) ones.
//   --baseline-update merges current violations into the sidecar and exits 0 (accept new debt deliberately).

#include "model.h"
#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on a malformed path-regex (never throw at match time)
#include "hashutil.h"      // sanitizer-clean modulo-2^64 FNV multiplication

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <regex>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

namespace ctx
{

// ── built-in architecture layers (P3): dir-name → layer, so a common repo layout gets a `layer=` tag on its
//    file nodes (architecture at a glance) WITHOUT the user declaring `layer NAME = …`. Matched against each
//    DIRECTORY component of the path (the filename segment is ignored), case-insensitive; first table hit
//    wins. The table is the absorb-plan §P3 set (canyon's `infrastucture` misspelling included on purpose).
struct BuiltinLayer { std::string_view dir; const char* layer; };

inline constexpr std::array<BuiltinLayer, 18> kBuiltinLayers = {{
    { "game", "game" },   { "gameplay", "game" },
    { "infra", "infra" }, { "infrastructure", "infra" }, { "infrastucture", "infra" },
    { "metal", "render" },{ "render", "render" },        { "renderer", "render" },
    { "math", "math" },   { "numerics", "math" },
    { "sound", "audio" }, { "audio", "audio" },
    { "steer", "ai" },    { "ai", "ai" },                { "behavior", "ai" },
    { "test", "test" },   { "tests", "test" },           { "bench", "test" },
}};

inline bool ciEqualAscii( std::string_view a, std::string_view b ) noexcept
{
    if( a.size() != b.size() ) return false;
    for( std::size_t i = 0; i < a.size(); ++i )
        if( std::tolower( static_cast<unsigned char>( a[i] ) ) != static_cast<unsigned char>( b[i] ) )
            return false;
    return true;
}

// First built-in layer matching any DIRECTORY component of `path` (filename ignored), or "" if none.
inline const char* builtinLayer( std::string_view path ) noexcept
{
    const std::size_t lastSlash = path.rfind( '/' );
    if( lastSlash == std::string_view::npos ) return "";          // no directory → no layer
    const std::string_view dirs = path.substr( 0, lastSlash );
    std::size_t start = 0;
    while( start <= dirs.size() )
    {
        const std::size_t      slash = dirs.find( '/', start );
        const std::string_view comp  = dirs.substr( start, ( slash == std::string_view::npos ? dirs.size() : slash ) - start );
        for( const BuiltinLayer& bl : kBuiltinLayers )
            if( ciEqualAscii( comp, bl.dir ) ) return bl.layer;
        if( slash == std::string_view::npos ) break;
        start = slash + 1;
    }
    return "";
}

// ── ABS-4: regex PATH-rules with capture-group backreferences ─────────────────────────────────────────
//
// A path-rule matches a dependency EDGE (src file → dst file) by two ECMAScript regexes over the file
// paths, with sibling-isolation via backreferences. Grammar (whitespace-tokenised, '#' = comment):
//
//   deny  path <FROM_REGEX> -> <TO_REGEX>
//   allow path <FROM_REGEX> -> <TO_REGEX>
//
//   FROM_REGEX is matched (std::regex_search) against the SRC file's ROOT-RELATIVE path (see the note at the
//   top of this file: an unanchored regex_search would otherwise bind to the checkout directory's own name —
//   a fixture checked out as `wt-cf2src` made `src/(\w+)/.*` capture the wrong segment and turned 4
//   violations into 7). On a hit, each capture group
//   1..9 is captured. TO_REGEX is then matched against the DST path AFTER substituting \1..\9 with the
//   REGEX-ESCAPED literal text of the corresponding FROM capture — so a `(?!\1/)` in TO_REGEX becomes a
//   negative-lookahead against THIS edge's own captured sibling, expressing "must not depend on a
//   *different* sibling". Example (feature dirs isolated unless explicitly allowed):
//
//   deny path src/(\w+)/.* -> src/(?!\1/)\w+/.*
//
//   means: a file under src/<X>/ may not depend on src/<Y>/ for any Y != X. `allow path` is an explicit
//   EXCEPTION — if a deny would fire on an edge but an allow path-rule ALSO matches it, the edge is
//   permitted (allow wins). Determinism: rules are applied in file order; the match is pure regex (no
//   global/mutable state). Soundness: a malformed FROM/TO regex is SKIPPED at parse time (kept but
//   flagged `bad`, never compiled into a matcher) so it can never fire, hang, or crash — std::regex on a
//   BOUNDED corpus terminates, and the substituted-backreference text is regex-escaped so a captured
//   path segment can never inject a pathological sub-pattern.
struct PathRule
{
    std::string from;        // FROM_REGEX source (as written)
    std::string to;          // TO_REGEX source (with \1..\9 placeholders, pre-substitution)
    bool        allow;       // true ⇒ allow (exception); false ⇒ deny
    bool        bad;         // true ⇒ FROM (or a no-backref TO) failed to compile → rule is inert (skipped)
    std::regex  fromRe;      // compiled FROM matcher (only valid when !bad)
};

struct ArchRules
{
    std::vector<std::string>              layerNames;   // index = layer id
    std::vector<std::vector<std::string>> layerSubs;    // parallel: path substrings defining each layer
    struct Rule { int from; int to; bool allow; };      // from/to = layer id, or -1 for '*'
    std::vector<Rule>     rules;
    std::vector<PathRule> pathRules;                     // ABS-4: regex path-rules (sibling isolation)
    bool loaded = false;
    bool parseError = false;   // D9: loaded==false BECAUSE a non-comment line was malformed (vs the file
                                // simply not opening) — parseArchRules already printed the specific reason
                                // to stderr, so the caller must not print its own generic "cannot read" on
                                // top of it (that would misdescribe a syntax error as a missing file).
};

// Escape every ECMAScript-regex metacharacter in `s` so it matches literally — used to splice a captured
// path segment into a TO_REGEX backreference without letting it inject sub-pattern syntax.
inline std::string regexEscapeLiteral( std::string_view s )
{
    std::string out;
    out.reserve( s.size() + 8 );
    for( char c : s )
    {
        switch( c )
        {
            case '.': case '^': case '$': case '|': case '(': case ')': case '[': case ']':
            case '{': case '}': case '*': case '+': case '?': case '\\': case '/':
                out.push_back( '\\' );
                [[fallthrough]];
            default:
                out.push_back( c );
        }
    }
    return out;
}

// Substitute \1..\9 in a TO_REGEX template with the regex-escaped literal of the matching FROM capture.
// An out-of-range or absent group substitutes empty (a rule referencing a group its FROM never captured
// simply never matches a real sibling — inert, not an error). A literal "\\" passes through unchanged.
inline std::string substituteBackrefs( std::string_view toTemplate, const std::smatch& m )
{
    std::string out;
    out.reserve( toTemplate.size() + 16 );
    for( std::size_t i = 0; i < toTemplate.size(); ++i )
    {
        if( toTemplate[i] == '\\' && i + 1 < toTemplate.size() )
        {
            const char nxt = toTemplate[ i + 1 ];
            if( nxt >= '1' && nxt <= '9' )
            {
                const std::size_t grp = std::size_t( nxt - '0' );
                if( grp < m.size() && m[ grp ].matched ) out += regexEscapeLiteral( m[ grp ].str() );
                i += 1;                                   // consume the digit
                continue;
            }
            // not a backref (e.g. \w, \d, \.) — keep the backslash AND the next char verbatim
            out.push_back( '\\' );
            out.push_back( nxt );
            i += 1;
            continue;
        }
        out.push_back( toTemplate[i] );
    }
    return out;
}

// Does the regex path-rule set FORBID the edge src→dst? deny path-rule matches the (src,dst) pair AND no
// allow path-rule matches it (allow = explicit exception). `bad` (uncompilable) rules are skipped — they
// can never fire. Pure function of its inputs (deterministic). Returns the 0-based index of the matching
// DENY rule via `outRuleIndex` (for a stable label) when it returns true; otherwise leaves it untouched.
inline bool pathRuleForbids( const ArchRules& r, std::string_view src, std::string_view dst, std::size_t& outRuleIndex )
{
    const std::string srcS( src ), dstS( dst );

    // 1) is the edge explicitly ALLOWED by any allow path-rule? (exception wins → never a violation)
    for( const PathRule& pr : r.pathRules )
    {
        if( pr.bad || !pr.allow ) continue;
        std::smatch fm;
        if( !std::regex_search( srcS, fm, pr.fromRe ) ) continue;
        std::regex toRe;
        try { toRe = std::regex( substituteBackrefs( pr.to, fm ), std::regex::ECMAScript ); }
        catch( const std::regex_error& ) { continue; }       // malformed-after-substitution → inert
        if( std::regex_search( dstS, toRe ) ) return false;   // an allow rule matches → permitted
    }

    // 2) does any DENY path-rule match? (first match wins for the label, file order = deterministic)
    for( std::size_t i = 0; i < r.pathRules.size(); ++i )
    {
        const PathRule& pr = r.pathRules[i];
        if( pr.bad || pr.allow ) continue;
        std::smatch fm;
        if( !std::regex_search( srcS, fm, pr.fromRe ) ) continue;
        std::regex toRe;
        try { toRe = std::regex( substituteBackrefs( pr.to, fm ), std::regex::ECMAScript ); }
        catch( const std::regex_error& ) { continue; }       // malformed-after-substitution → inert
        if( std::regex_search( dstS, toRe ) ) { outRuleIndex = i; return true; }
    }
    return false;
}

inline int archLayerId( const ArchRules& r, std::string_view name )   // name → id; '*' → -1; unknown → -2
{
    if( name == "*" ) return -1;
    for( std::size_t i = 0; i < r.layerNames.size(); ++i ) if( r.layerNames[i] == name ) return int( i );
    return -2;
}

// Returns the set of dir-component substrings for a built-in layer name, or empty if name is not a built-in.
// Used by parseArchRules to auto-populate layers referenced by name but not declared by the user.
//
// archLayerOf uses path.find(s) for bare substring matching.  Bare dir names like "render" would match
// anywhere in a path (e.g. "test/archfix/render/..." AND "test/archfix/renderer_test/...").  We emit two
// slash-anchored forms that force directory-component semantics:
//   "/render/"   — matches the dir as a non-first, non-last component
//   "render/"    — matches when the dir is the very first path component (no leading slash)
// Together these cover every case without false-positive substring hits.
inline std::vector<std::string> builtinLayerSubs( std::string_view name ) noexcept
{
    std::vector<std::string> subs;
    for( const BuiltinLayer& bl : kBuiltinLayers )
    {
        if( name != bl.layer ) continue;
        // mid-path form: "/dir/"  e.g. "/render/"
        const std::string mid = std::string( "/" ) + std::string( bl.dir ) + "/";
        // root-path form: "dir/"  e.g. "render/"  (handles paths that start with the dir name)
        const std::string root = std::string( bl.dir ) + "/";
        // dedup before inserting
        bool hasMid = false, hasRoot = false;
        for( const std::string& s : subs ) { if( s == mid ) hasMid = true; if( s == root ) hasRoot = true; }
        if( !hasMid  ) subs.push_back( mid  );
        if( !hasRoot ) subs.push_back( root );
    }
    return subs;
}

inline ArchRules parseArchRules( const std::string& path )
{
    ArchRules r;
    std::ifstream f( path );
    if( !f ) return r;   // can't open at all — caller reports "cannot read rules file" (r.parseError stays false)

    // collect raw rule tokens in file order; resolve ids AFTER all user `layer` lines are seen,
    // then auto-add built-in layers for names that still have no definition.
    struct RawRule { std::string from; std::string to; bool allow; };
    std::vector<RawRule> rawRules;

    // D9 fix: adopt --lint-rules' loud-refusal discipline (lintrules.h::parseLintRuleFile) instead of the
    // old silent-drop. A CI arch gate that a typo turns into `rules="0" violations="0"` exit-0 is a WORSE
    // failure mode than refusing to run — the whole point of --arch is to fail loud on a violation, and a
    // rules file that silently parsed to nothing defeats that for every line after the typo, not just the
    // one line. Every non-blank, non-comment line MUST resolve to a recognized, well-formed rule/layer;
    // the first one that doesn't aborts the WHOLE file with a specific `path:lineNo: reason` message,
    // mirroring parseLintRuleFile's badLine/"file skipped" contract exactly.
    const auto badLine = [ & ]( std::size_t lineNo, const char* why ) -> bool
    {
        std::fprintf( stderr, "ctxpack: --arch: %s:%zu: %s — rules file rejected\n", path.c_str(), lineNo, why );
        DEGRADED_PATH_ALERT( "arch: malformed rules line — rules file rejected" );
        return false;
    };

    std::string line;
    std::size_t lineNo = 0;
    bool        ok     = true;
    while( ok && std::getline( f, line ) )
    {
        ++lineNo;
        const std::size_t h = line.find( '#' );
        if( h != std::string::npos ) line.resize( h );        // strip comment
        std::istringstream ss( line );
        std::string kw;
        if( !( ss >> kw ) ) continue;                          // blank (or comment-only) line — fine
        if( kw == "layer" )
        {
            std::string name, eq, s;
            ss >> name >> eq;                                  // layer NAME = ...
            std::vector<std::string> subs;
            while( ss >> s ) subs.push_back( s );
            if( name.empty() || eq != "=" || subs.empty() ) { ok = badLine( lineNo, "malformed line (want: layer NAME = sub1 sub2 ...)" ); break; }
            r.layerNames.push_back( name ); r.layerSubs.push_back( std::move( subs ) );
        }
        else if( kw == "allow" || kw == "deny" )
        {
            std::string tok1;
            ss >> tok1;
            if( tok1.empty() ) { ok = badLine( lineNo, "malformed line (want: allow|deny FROM -> TO, or allow|deny path FROM_REGEX -> TO_REGEX)" ); break; }
            if( tok1 == "path" )                               // ABS-4: `deny|allow path <FROM_REGEX> -> <TO_REGEX>`
            {
                std::string fromRe, arrow, toRe;
                ss >> fromRe >> arrow >> toRe;                  // tokens are whitespace-free regexes (no spaces in a path)
                if( fromRe.empty() || arrow != "->" || toRe.empty() )
                { ok = badLine( lineNo, "malformed line (want: allow|deny path FROM_REGEX -> TO_REGEX)" ); break; }
                PathRule pr;
                pr.from  = fromRe;
                pr.to    = toRe;
                pr.allow = ( kw == "allow" );
                pr.bad   = false;
                // Compile the FROM regex now; a malformed PATTERN (well-formed line, bad regex syntax) is
                // kept-but-flagged `bad` so it can NEVER fire (the soundness guard — no hang, no throw at
                // match time) — a semantic issue, not the structural "line didn't parse" this fix targets,
                // so it stays a soft degrade rather than rejecting the whole file. The TO regex is compiled
                // per-edge after backref substitution (so it is validated there too).
                try { pr.fromRe = std::regex( fromRe, std::regex::ECMAScript ); }
                catch( const std::regex_error& ) { pr.bad = true; DEGRADED_PATH_ALERT( "arch: malformed FROM path-regex — rule skipped" ); }
                r.pathRules.push_back( std::move( pr ) );
            }
            else                                               // layer-name rule: `allow|deny FROM -> TO`
            {
                std::string arrow, to;
                ss >> arrow >> to;                             // tok1 = FROM; then -> TO
                if( arrow != "->" || to.empty() ) { ok = badLine( lineNo, "malformed line (want: allow|deny FROM -> TO)" ); break; }
                rawRules.push_back( { tok1, to, kw == "allow" } );
            }
        }
        else
        {
            ok = badLine( lineNo, "unrecognized keyword (want 'layer', 'allow', or 'deny')" );
            break;
        }
    }
    if( !ok ) { r.parseError = true; return r; }   // r.loaded stays false — the whole file is rejected, like --lint-rules

    // P3-B: for each rule referencing an unknown name that IS a built-in layer, auto-add it.
    // User-defined layers win on name clash (they are already in layerNames above); we only add
    // built-ins for names not yet defined. Built-in entries are appended AFTER user layers so
    // archLayerOf (first-match-wins) tries user layers first.
    for( const RawRule& rr : rawRules )
    {
        for( const std::string* namePtr : { &rr.from, &rr.to } )
        {
            if( *namePtr == "*" ) continue;                   // wildcard, always valid
            if( archLayerId( r, *namePtr ) != -2 ) continue;  // already defined → skip
            std::vector<std::string> subs = builtinLayerSubs( *namePtr );
            if( !subs.empty() ) { r.layerNames.push_back( *namePtr ); r.layerSubs.push_back( std::move( subs ) ); }
        }
    }

    // resolve raw rules to layer ids now that all layers (user + auto-added built-ins) are known
    for( const RawRule& rr : rawRules )
    {
        const int fi = archLayerId( r, rr.from ), ti = archLayerId( r, rr.to );
        if( fi != -2 && ti != -2 ) r.rules.push_back( { fi, ti, rr.allow } );
    }

    r.loaded = true;
    return r;
}

inline int archLayerOf( const ArchRules& r, std::string_view path )   // first matching layer, or -1 (unlayered)
{
    for( std::size_t i = 0; i < r.layerSubs.size(); ++i )
        for( const std::string& s : r.layerSubs[i] )
            if( path.find( s ) != std::string_view::npos ) return int( i );
    return -1;
}

// Is the edge layer la → layer lb a violation? deny match OR (la is allow-listed AND lb not allowed). -1='*'.
inline bool archViolates( const ArchRules& r, int la, int lb )
{
    bool hasAllow = false, allowed = false, denied = false;
    for( const ArchRules::Rule& rule : r.rules )
    {
        const bool fromM = ( rule.from == -1 || rule.from == la );
        const bool toM   = ( rule.to   == -1 || rule.to   == lb );
        if( rule.allow && fromM )           hasAllow = true;   // wildcard `allow * -> X` allow-lists every layer too
        if( rule.allow && fromM && toM )    allowed  = true;
        if( !rule.allow && fromM && toM )   denied   = true;
    }
    return denied || ( hasAllow && !allowed );
}

// ── S5-B: --arch --baseline helpers ──────────────────────────────────────────────────────────────────
//
// Hash function: inline FNV-1a 64 — the same family already used in main.cpp (defaultCachePath).
// Key = src_file + '\0' + dst_file + '\0' + rule_label (the matched layer-name pair).
// NOT stable across renames (intentional: a renamed file that still violates gets re-baselined).

inline std::uint64_t fnv1a64( std::string_view s ) noexcept
{
    std::uint64_t h = 14695981039346656037ull;
    for( unsigned char c : s ) { h ^= c; h = hashutil::fnv1aMultiply( h ); }
    return h;
}

// ── S2: root-relative path for BASELINE HASHING (committed-sidecar portability) ───────────────────────
//
// Both baseline sidecars (.ctxpack_arch_baseline, .ctxpack_quality_baseline) are meant to be COMMITTED and
// portable. But every path in ing.files is spelled `<ingest-root>/<relative>` verbatim — the crawl just
// prepends the root argument. So `ctxpack .` embeds `./game/x.cpp` while `ctxpack /abs/repo` embeds
// `/abs/repo/game/x.cpp`, giving DIFFERENT hashes for the same file → a baseline written under one root
// spelling falsely fails enforcement under another (exit 0 vs 2 for a teammate/CI with a different root).
//
// relForHash strips the ingest-root prefix LEXICALLY (never a realpath — that would be nondeterministic and
// pull in the filesystem, and would break on a symlinked/`..`-containing root), producing the SAME
// root-relative key for both spellings. Every use is a root-spelling NORMALIZATION of exactly this shape:
// the baseline hash paths, and — W3FIX — the --dead-code `./`-anchored path filter, whose "position 0 is the
// repo root" rule holds only for a root-relative path and so silently matched nothing under an absolute root
// spelling. It never touches `canonId`, the emitted `id=` attribute, resolution, or the default map (see the
// S2 trap: canonId is load-bearing far beyond the baseline), and it is never an emitted VALUE — only ever a
// comparison key. Determinism: pure function of (path, root); no I/O, no state.
//
// The strip is: remove a leading `root` prefix (with an optional trailing '/'), then normalize any residual
// leading `./` and leading `/`. A path that does not start with `root` (shouldn't happen — every file is
// under the crawl root) is returned only leading-`./`/`/`-normalized, so it degrades to a stable key rather
// than an empty one. Empty root ⇒ just the leading-`./`/`/` normalization (equivalent to root ".").
inline std::string_view relForHash( std::string_view path, std::string_view root ) noexcept
{
    // 1) strip the ingest-root prefix if present (allow one optional trailing '/' on the root).
    std::string_view rootTrim = root;
    while( rootTrim.size() > 1 && rootTrim.back() == '/' ) rootTrim.remove_suffix( 1 );   // "/abs/repo/" → "/abs/repo"
    if( !rootTrim.empty() && rootTrim != "." && path.size() >= rootTrim.size()
        && path.compare( 0, rootTrim.size(), rootTrim ) == 0 )
    {
        // matched the root; the next char (if any) must be a '/' so we strip whole path components only
        // ("/abs/repo" must not eat the "repo" in "/abs/repository/...").
        std::string_view rest = path.substr( rootTrim.size() );
        if( rest.empty() || rest.front() == '/' ) path = rest;
    }

    // 2) normalize residual leading "./" then leading "/" so "." / "./x" / "/x" all collapse to "x".
    while( path.size() >= 2 && path[0] == '.' && path[1] == '/' ) path.remove_prefix( 2 );
    while( !path.empty() && path.front() == '/' ) path.remove_prefix( 1 );
    while( path.size() >= 2 && path[0] == '.' && path[1] == '/' ) path.remove_prefix( 2 );
    return path;
}

// Stable hash for one arch violation. rule_label = "FROM->TO" (the layer names, not the file paths).
inline std::uint64_t archViolHash( std::string_view srcFile,
                                   std::string_view dstFile,
                                   std::string_view ruleLabel ) noexcept
{
    // Concatenate with NUL separators so "a/b" + "c" and "a" + "b/c" produce different hashes.
    std::uint64_t h = 14695981039346656037ull;
    const auto mix = [ &h ]( std::string_view sv ) noexcept
    {
        for( unsigned char c : sv ) { h ^= c; h = hashutil::fnv1aMultiply( h ); }
        h ^= 0u; h = hashutil::fnv1aMultiply( h );   // NUL separator byte
    };
    mix( srcFile );
    mix( dstFile );
    mix( ruleLabel );
    return h;
}

// Sidecar file name written next to the rules file (or in CWD when rules file has no dir component).
// Using a fixed name in CWD keeps it repo-committable and rules-file-independent; the user adds it to .gitignore or commits it.
inline std::string archBaselinePath( const std::string& /*rulesPath*/ ) noexcept
{
    return ".ctxpack_arch_baseline";
}

// Read the baseline sidecar.  Returns the set of violation hashes committed as accepted debt.
// Returns empty set if the file does not exist (first run) — callers treat that as "no baseline".
inline std::unordered_set<std::uint64_t> archReadBaseline( const std::string& sidecarPath ) noexcept
{
    std::unordered_set<std::uint64_t> hashes;
    std::ifstream f( sidecarPath );
    if( !f ) return hashes;
    std::string line;
    while( std::getline( f, line ) )
    {
        // skip comment lines (start with '#') and blank lines
        if( line.empty() || line[0] == '#' ) continue;
        char*               end = nullptr;
        const std::uint64_t h   = std::strtoull( line.c_str(), &end, 16 );
        if( end != line.c_str() ) hashes.insert( h );
    }
    return hashes;
}

// Write (or overwrite) the baseline sidecar with exactly the given hash set, sorted for determinism.
// Returns true on success.
inline bool archWriteBaseline( const std::string&                         sidecarPath,
                               const std::unordered_set<std::uint64_t>&   hashes ) noexcept
{
    std::vector<std::uint64_t> sorted( hashes.begin(), hashes.end() );
    std::sort( sorted.begin(), sorted.end() );

    std::FILE* f = std::fopen( sidecarPath.c_str(), "w" );
    if( !f ) return false;
    std::fprintf( f, "# ctxpack arch baseline — do not edit by hand. Regenerate with --baseline or --baseline-update.\n" );
    for( std::uint64_t h : sorted )
        std::fprintf( f, "%016llx\n", static_cast<unsigned long long>( h ) );
    std::fclose( f );
    return true;
}

// ── ABS-4: Robert C. Martin package metrics + reachability, per MODULE (= directory) ──────────────────
//
// EVIDENCE NOTE: I/A/D ("main sequence" distance) is widely implemented (NDepend, Sonargraph, here) but
// no independent outcome-based study validates that D predicts defects or maintenance cost — a design
// heuristic, not proof (RESEARCH_agentQuality2026 §1a). Ca/Ce (raw coupling counts) sit on firmer ground:
// coupling itself IS validated; it's the derived I/A/D distance metric that lacks independent validation.
//
// APPROXIMATION DISCLAIMER (load-bearing — do not over-claim): a "module" here is a file's immediate
// parent DIRECTORY, and the module dependency graph is the DIRECTORY projection of the FILE→FILE
// #include/import graph, which is itself name-based (basename-resolved, see resolveIncludeAdj). So Ca/Ce
// and the derived I/A/D are DIRECTORY-LEVEL ESTIMATES from name-based edges, not a type-checked package
// model. They are reproducible and useful for "which dir is in the zone of pain", not a formal proof.
//
// Metrics (Martin):
//   Ca = afferent coupling  = # OTHER modules that depend ON this module (module in-degree)
//   Ce = efferent coupling  = # OTHER modules this module depends ON     (module out-degree)
//   I  = instability        = Ce / (Ca + Ce)   in [0,1]; 0/0 (isolated) → 0 (stable-by-vacuity, documented)
//   A  = abstractness       = abstract_types / total_types in the module; no types → 0 (documented)
//   D  = distance           = |A + I - 1|       in [0,1]; 0 = on the main sequence, →1 = pain/useless
//   zone: "pain"    = concrete + stable  (A small, I small) and D high — rigid, hard to change
//         "useless" = abstract + unstable (A large, I large) and D high — abstractions nothing uses
//         "ok"      = otherwise
//
// Abstractness proxy (from the tags ctxpack already has — NO new parser pass):
//   a TYPE = a Class/Struct/Interface symbol. It is ABSTRACT when it is SymKind::Interface (a TS/Go
//   interface, Swift/ObjC protocol → abstract by definition) OR it is a Class/Struct that DECLARES at
//   least one method with NO BODY (endByte <= sigEndByte) — a pure-virtual / abstract-method declaration,
//   the standard "abstract class" signal in C++. Method→class membership is by Symbol.scope == class name
//   within the same module (conservative; scope is populated for C++/Python).
//
// Reachability entry-point heuristic (documented choice): entries = every module that defines a symbol
// named `main` UNION every DAG ROOT (a module with Ca == 0). A pure source/driver dir that nothing
// imports is thus an entry (correctly LIVE), and a `main`-bearing dir is an entry even if imported. A
// module NOT in the forward closure of that entry set over module→module edges is reachable=0 (a
// candidate dead island). isolated = (Ca == 0 && Ce == 0); leaf = (Ce == 0 && Ca > 0).
//
// zone classification (Martin main-sequence): assigned only once D exceeds kZoneDistanceThreshold — below
// that, the module sits close enough to the main sequence to call "ok" regardless of which side it leans.
// Past the threshold, the (A,I) point is split by which side of the A+I=1 line it falls on:
//   A + I <  kZoneBalancePoint (1.0)  → "pain"    (low-I low-A corner: concrete AND stable → rigid)
//   A + I >= kZoneBalancePoint (1.0)  → "useless" (high-I high-A corner: abstract AND nothing depends on it)
// Tie-break: D exactly == kZoneDistanceThreshold is NOT "past" it (strict '>') → falls to "ok", deterministic.
// FOLKLORE (not independently validated — RESEARCH_agentQuality2026 §1a): these corners are Martin's design
// heuristic, descriptive only; ctxpack does not claim they predict defects or maintenance cost.
inline constexpr double kZoneDistanceThreshold = 0.5;   // |A+I-1| past this → classify into pain/useless
inline constexpr double kZoneBalancePoint      = 1.0;   // the A+I split line between the pain and useless corners

struct ModuleMetric
{
    std::string   path;          // the directory path (the module id)
    std::uint32_t ca = 0;        // afferent: # modules depending on this one
    std::uint32_t ce = 0;        // efferent: # modules this one depends on
    std::uint32_t totalTypes = 0;
    std::uint32_t abstractTypes = 0;
    double        instability = 0.0;   // I
    double        abstractness = 0.0;  // A
    double        distance = 0.0;      // D
    const char*   zone = "ok";         // "pain" | "useless" | "ok"
    bool          reachable = true;    // false ⇒ not reachable from any entry point (candidate dead)
    bool          isolated = false;    // Ca==0 && Ce==0
    bool          isLeaf = false;      // Ce==0 && Ca>0  (depends on nothing, but depended on)
};

// Compute the per-module Martin metrics + reachability. `adj` = the file→file dependency graph
// (resolveIncludeAdj: adj[f] = files f includes). Deterministic: modules indexed in first-seen file
// order then the RESULT is sorted by path; every set is built via sorted/deduped vectors, never iterated
// out of a hash map into output. `distThreshold` flags zone when D exceeds it (defaults to the named
// kZoneDistanceThreshold constexpr above; every current call site uses the default).
inline std::vector<ModuleMetric> computeModuleMetrics( const IngestResult& ing,
                                                       const std::vector<std::vector<std::uint32_t>>& adj,
                                                       double distThreshold = kZoneDistanceThreshold )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );

    // file → module (directory) id; module paths kept in first-seen order (compacted, deterministic).
    const auto dirOf = []( std::string_view p ) -> std::string_view
    {
        const std::size_t sl = p.rfind( '/' );
        return sl == std::string_view::npos ? std::string_view( "." ) : p.substr( 0, sl );
    };
    HashMap<std::string, std::uint32_t> modId;
    std::vector<std::string>            modPath;
    std::vector<std::uint32_t>          fileMod( F, 0 );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        const std::string d( dirOf( ing.files[f] ) );
        const auto [ it, inserted ] = modId.try_emplace( d, std::uint32_t( modPath.size() ) );
        if( inserted ) modPath.push_back( d );
        fileMod[f] = it->second;
    }
    const std::uint32_t M = std::uint32_t( modPath.size() );

    // module → module forward edges (deduped, sorted). Folds the file→file graph up to the directory.
    std::vector<std::vector<std::uint32_t>> mout( M );   // modules this one depends ON
    {
        std::vector<std::unordered_set<std::uint32_t>> seen( M );
        for( std::uint32_t f = 0; f < F; ++f )
            for( std::uint32_t g : adj[f] )
            {
                if( g >= F ) continue;
                const std::uint32_t a = fileMod[f], b = fileMod[g];
                if( a == b ) continue;                   // intra-module include → not a module edge
                if( seen[a].insert( b ).second ) mout[a].push_back( b );
            }
        for( std::uint32_t m = 0; m < M; ++m ) std::sort( mout[m].begin(), mout[m].end() );
    }
    // Ca / Ce per module.
    std::vector<std::uint32_t> ce( M, 0 ), ca( M, 0 );
    for( std::uint32_t m = 0; m < M; ++m ) { ce[m] = std::uint32_t( mout[m].size() ); for( std::uint32_t b : mout[m] ) ++ca[b]; }

    // abstractness counts per module from the symbol tags (no new parse pass).
    // 1) which CLASS/STRUCT symbols declare a bodyless method? membership = method.scope == class.name in
    //    the same module. Build (module, className) → hasPureVirtual, then per type decide abstract.
    const auto hasBody = [ & ]( const Symbol& s ) noexcept { return s.endByte > s.sigEndByte; };
    HashMap<std::string, char> moduleClassPure;          // key = "<modId>#<className>" → '1' if a bodyless method seen
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind != SymKind::Method ) continue;
        if( hasBody( s ) ) continue;                     // only a DECLARATION (pure-virtual / abstract) counts
        if( s.scope.empty() ) continue;
        const std::uint32_t m = fileMod[ s.fileId ];
        moduleClassPure[ std::to_string( m ) + "#" + s.scope ] = '1';
    }
    std::vector<std::uint32_t> totalTypes( M, 0 ), abstractTypes( M, 0 );
    for( const Symbol& s : ing.symbols )
    {
        const bool isType = ( s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface );
        if( !isType ) continue;
        const std::uint32_t m = fileMod[ s.fileId ];
        ++totalTypes[m];
        bool abstractT = ( s.kind == SymKind::Interface );   // a TS/Go interface / Swift-ObjC protocol → abstract
        if( !abstractT )
            abstractT = moduleClassPure.find( std::to_string( m ) + "#" + s.name ) != moduleClassPure.end();   // ≥1 pure-virtual method
        if( abstractT ) ++abstractTypes[m];
    }

    // reachability: entries = modules with a `main` symbol ∪ DAG roots (Ca == 0). Forward BFS over mout.
    std::vector<char> isEntry( M, 0 );
    for( std::uint32_t m = 0; m < M; ++m ) if( ca[m] == 0 ) isEntry[m] = 1;   // every DAG root is a live entry
    for( const Symbol& s : ing.symbols )
        if( s.name == "main" && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) ) isEntry[ fileMod[ s.fileId ] ] = 1;
    std::vector<char>          reach( M, 0 );
    std::vector<std::uint32_t> q;
    for( std::uint32_t m = 0; m < M; ++m ) if( isEntry[m] && !reach[m] ) { reach[m] = 1; q.push_back( m ); }
    for( std::size_t head = 0; head < q.size(); ++head )
        for( std::uint32_t b : mout[ q[head] ] ) if( !reach[b] ) { reach[b] = 1; q.push_back( b ); }

    // assemble + compute I/A/D + zone, then sort by path for a stable emit order.
    std::vector<ModuleMetric> out;
    out.reserve( M );
    for( std::uint32_t m = 0; m < M; ++m )
    {
        ModuleMetric mm;
        mm.path          = modPath[m];
        mm.ce            = ce[m];
        mm.ca            = ca[m];
        mm.totalTypes    = totalTypes[m];
        mm.abstractTypes = abstractTypes[m];
        const double sum = double( ca[m] ) + double( ce[m] );
        mm.instability   = sum > 0.0 ? double( ce[m] ) / sum : 0.0;                       // 0/0 isolated → 0 (documented)
        mm.abstractness  = totalTypes[m] > 0 ? double( abstractTypes[m] ) / double( totalTypes[m] ) : 0.0;   // no types → 0
        mm.distance      = std::fabs( mm.abstractness + mm.instability - 1.0 );
        mm.isolated      = ( ca[m] == 0 && ce[m] == 0 );
        mm.isLeaf        = ( ce[m] == 0 && ca[m] > 0 );
        mm.reachable     = ( reach[m] != 0 );
        // §P6.5: a module with NO types (totalTypes==0 — a pure doc/bench/free-function dir) cannot
        // meaningfully have an abstractness score: A is forced to 0 by definition (line 661), which pins
        // D = |0 + I - 1| = 1 - I close to 1 for any low-instability module, so EVERY such module reads as
        // "pain" regardless of its actual coupling shape — on the real repo this was 132 of 163 modules,
        // nearly all typeless. zone="n/a" says "not classifiable", not "classified and bad"; excluded from
        // the zone_pain/zone_useless header tally below (main.cpp emitMetrics) so the ratio a reader
        // computes is over modules that CAN carry the metric, not the whole corpus.
        if( mm.totalTypes == 0 )
            mm.zone = "n/a";
        // zone only when D is past the threshold; pain = concrete+stable corner, useless = abstract+unstable.
        else if( mm.distance > distThreshold )
            mm.zone = ( mm.abstractness + mm.instability < kZoneBalancePoint ) ? "pain" : "useless";
        else
            mm.zone = "ok";
        out.push_back( std::move( mm ) );
    }
    std::sort( out.begin(), out.end(), []( const ModuleMetric& a, const ModuleMetric& b ) { return a.path < b.path; } );
    return out;
}

// ── Q5b: DSM propagation cost (MacCormack-Rusnak-Baldwin MgmtSci'06) ──────────────────────────────────
//
// Propagation cost = the DENSITY of the transitive closure ("visibility matrix") of the file→file
// dependency graph = the fraction of the system reachable from an average file:
//
//     propagation_cost = ( Σ_i |reachable(i)| ) / N²          (N = file count)
//
// where reachable(i) is the set of files transitively reachable from file i INCLUDING i itself — the
// canonical MacCormack visibility matrix has a UNIT DIAGONAL (a component always "sees" itself). A high
// value means most files transitively depend on most others (change ripples widely → high maintenance
// cost); a low value means changes stay local. VALIDATED coupling form (§1a) — reported, never a gate.
//
// This is a SYSTEM-level architecture fact, so it is emitted as a single reported NUMBER (fixed 3-decimal
// precision → byte-identical run-to-run; it is a report value, not a rank input, so no tolerance band).
//
// Determinism: a per-node BFS over a `visited` bitset in ascending file-id order; the RATIO is order-
// independent (a sum of set sizes), and the fixed formatting pins the emitted string. adj[f] may hold
// duplicate or out-of-range ids (see resolveIncludeAdj) — the bitset dedups and `g < F` skips the latter.
//
// Complexity: O( N · (N + E) ) worst case (one BFS per file). For a file→file graph (hundreds–thousands
// of files) this is trivial; NOT the O(N³) Floyd-Warshall closure. A dense 2000-file tree is ~a few M
// edge-visits — sub-millisecond. If a pathologically large + dense tree ever makes it material, a bitset-
// per-node reachability fold (word-parallel OR) is the drop-in upgrade; unneeded at current scale.
//
// Degrade / edge cases (never divides by zero):
//   N == 0 → 0.0 (empty graph, documented: no files → no propagation)
//   N == 1 → 1.0 (the sole file reaches only itself; Σ=1, N²=1 → 1.0, the unit-diagonal convention)
//
// The traversal core (sum of |reachable(root)| over a ROOT SET) is factored into sumReachableClosure below
// so §P9.4's dependency-capable-only view (dsmPropagationCostCapable) shares the exact same walk instead of
// a second copy of it — only the root set and the denominator N differ between the two views.
inline std::uint64_t sumReachableClosure( const std::vector<std::vector<std::uint32_t>>& adj,
                                          const std::vector<std::uint32_t>&              roots,
                                          std::uint32_t                                  F ) noexcept
{
    std::uint64_t              total = 0;
    std::vector<char>          visited( F, 0 );    // reused across BFS roots (reset for touched nodes only)
    std::vector<std::uint32_t> stack;              // explicit stack — no recursion on any thread
    stack.reserve( F );

    for( const std::uint32_t s : roots )
    {
        std::uint32_t              reachedCount = 0;
        std::vector<std::uint32_t> touched;       // nodes we set visited=1 for, to clear after this root
        touched.reserve( F );

        visited[s] = 1; touched.push_back( s ); ++reachedCount;   // unit diagonal: a file reaches itself
        stack.clear();
        stack.push_back( s );
        while( !stack.empty() )
        {
            const std::uint32_t v = stack.back();
            stack.pop_back();
            for( const std::uint32_t g : adj[v] )
            {
                if( g >= F ) continue;            // out-of-range id (resolveIncludeAdj can't, but guard)
                if( visited[g] ) continue;        // bitset dedups duplicate adjacency entries + revisits
                visited[g] = 1; touched.push_back( g ); ++reachedCount;
                stack.push_back( g );
            }
        }
        total += reachedCount;

        for( const std::uint32_t t : touched ) visited[t] = 0;    // O(reached) reset — no full-vector wipe
    }
    return total;
}

// §P9.4: N restricted to a ROOT SET of dependency-capable files (depCapable — see
// lintrules.h::dependencyCapable), the SAME mask `--deps <health>` uses (graph.h::restrictDependencyHealth)
// — a .sh/.md file can only ever be an isolated node (BFS root reaches only itself), so counting it in N²
// dilutes propagation_cost for a reason unrelated to actual coupling (measured on this repo: 385/760 files
// are .sh/.md). Only capable files seed a root and count toward N; a root's reachable SET can still legally
// pass through any node adj[] leads to (an edge into a non-capable path is possible in principle) —
// unchanged, only WHICH files seed a walk and the denominator are restricted.
inline double dsmPropagationCostCapable( const IngestResult&                            ing,
                                         const std::vector<std::vector<std::uint32_t>>& adj,
                                         const std::vector<char>&                       depCapable ) noexcept
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    if( F == 0 ) return 0.0;

    std::vector<std::uint32_t> roots;
    roots.reserve( F );
    for( std::uint32_t s = 0; s < F; ++s ) if( s < depCapable.size() && depCapable[s] ) roots.push_back( s );
    if( roots.empty() ) return 0.0;               // no dependency-capable file at all → 0 (documented)

    const std::uint64_t reachableTotal = sumReachableClosure( adj, roots, F );
    const double        n              = double( roots.size() );
    return double( reachableTotal ) / ( n * n );
}

// The unrestricted, whole-corpus view — every file is its own root set (N = ing.files.size()). A thin
// wrapper over dsmPropagationCostCapable (an all-ones mask) rather than a second copy of the same body, so
// the two views can never drift apart structurally.
inline double dsmPropagationCost( const IngestResult&                            ing,
                                  const std::vector<std::vector<std::uint32_t>>& adj ) noexcept
{
    return dsmPropagationCostCapable( ing, adj, std::vector<char>( ing.files.size(), 1 ) );
}

}   // namespace ctx
