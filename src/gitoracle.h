#pragma once

// gitoracle.h — the NAME-HISTORY ORACLE: "was this name ever in this repo, and when did it leave?"
//
// Two verbs shipped with the SAME documented hole, and it is this question:
//   * --doc-drift (docdrift.h) reports why="undefined" for a backticked name defined nowhere in the repo.
//     But defined-nowhere is NOT deleted: in a PLAN or DESIGN doc naming unbuilt work, absence is EXPECTED.
//     Measured on the neighbour app repo, 325 of its 575 drift rows were that lane, and 243 of those 325 were names
//     that were never here at all — the cry-wolf failure the verb's own header warns about.
//   * --whereis (crossref.h) scans each ref's TREE, so it can only find content that still EXISTS somewhere.
//     Content every tree has since dropped is invisible to it, however loudly HEAD's history remembers it.
// One oracle answers both, so neither has to grow its own git-history lane.
//
// ── which git probe, and why (the three candidates, measured) ────────────────────────────────────────────
// `git log -S<name>` is the PICKAXE: it selects commits where the NUMBER of occurrences of a literal string
// changed. That is precisely the "appeared / disappeared" question, it is literal with --pickaxe-regex off
// (so a name containing regex metacharacters cannot mean something else), and it is the fastest of the three.
// `git log -G<regex>` instead matches the diff TEXT, so it also selects commits that merely touched a line
// mentioning the name (a reindent, a neighbour's rename) — a different, noisier question, and it needs the
// name escaped into a regex. `--follow` answers a question about a PATH's rename chain, not about a NAME, so
// it does not apply at all. The pickaxe is the right SEMANTICS, and that is the semantics reproduced below.
//
// It is NOT, however, the right IMPLEMENTATION, because the pickaxe answers for ONE name per process:
//
//   a 2965-file, 1863-commit, 36-branch app repo, 247 distinct candidate names
//     (a) 247 x `git log -S<name> --oneline -1`                        ~126 s      <- why the gap existed
//     (a') same, walk bounded to a 300-commit rev range                 ~85 s      (still per-name; still hopeless)
//     (b) ONE `git log -p -U0` pass, tokenize the removed lines           3.0 s     <- 40x faster, and O(1) in names
//     (c) (b) prefiltered by a -G alternation of all 247 names          ~183 s      <- SLOWER than doing nothing
//
// (c) is the interesting negative result: handing git a 3.7 KB alternation makes it run that regex against
// every diff line of every commit, which costs far more than streaming the patch text out and tokenizing it
// here. So the shipped probe is (b): ONE `git log --no-merges -p -U0` walk, newest-commit-first, recording
// for every identifier on a REMOVED line the newest commit that removed it. Per-name cost is a hash lookup.
//
// ── why "newest removal" is exactly "when it left" ───────────────────────────────────────────────────────
// The oracle is only ever consulted for a name ABSENT from HEAD's tree — that is the caller's precondition
// (docdrift asks only about names its corpus pass found nowhere; whereis asks only when on-head="0"). Given
// that, every line that ever carried the name has since been removed, so the NEWEST removal is the moment
// the last occurrence went away. This is also what makes --no-renames safe: a rename shows as a full delete
// plus a full add, and the spurious delete can only concern a name that still exists at HEAD — which is a
// name we never ask about.
//
// ── ANCHORING: HEAD-anchored ON PURPOSE (r26 merge-base audit) ──────────────────────────────────────────
// The walk is a bare `git log` — every commit REACHABLE FROM HEAD, and nothing else. That is deliberate,
// and it is not the failure mode the r26 audit went looking for: this verb runs no ref-to-ref diff, so
// there is no "fires constantly because HEAD moved" here. The question it answers is literally about the
// live line's own history ("did THIS line ever carry the name, and when did it drop it"), and every note in
// kFateTable below is phrased "reachable from HEAD" so the scope is visible in the OUTPUT, not just here.
// The cost of that anchor, named rather than hidden: a name that only ever existed on — and was only ever
// removed on — an unmerged branch is invisible to the walk, and honestly reports fate="never". --whereis'
// TREE scan is the lane that covers branch-only content; the two are joined by the consumer, on purpose.
//
// ── cost discipline: opt-in, then never paid twice ───────────────────────────────────────────────────────
// 3.0 s (the neighbour app repo) / 0.83 s (this repo) against a warm --doc-drift of 0.64 s / 0.15 s is a 5-6x
// regression, so the probe is OPT-IN (--with-history) and never runs on the default path. The SECOND run is
// free: the result is memoized in a per-(repo, HEAD sha) cache blob under the same shaKeyedCachePath /
// exclConfigHex convention mergescout.h's "qms" family uses. A commit sha is immutable, so a sha-keyed cache
// can never go stale — and because the blob holds the WHOLE-repo removed-name map rather than one query's
// answers, --whereis reuses the map --doc-drift built (44,904 names / ~4 MB on the neighbour app repo; 11,062 / ~1 MB
// here). Determinism: the cached report is byte-for-byte the computed one, so warm output == cold output —
// asserted directly in test/historyoraclecheck.sh, because ingest.cpp learned this week what happens when a
// cached field and its cold twin drift apart.
//
// Read-only, always: one `git log` and nothing else. Never checks out, never writes a ref, never touches the
// working tree.

#include "model.h"
#include "quality.h"      // gitHeadSha / gitRepoHasHistory / cacheDirLadder / shaKeyedCachePath / exclConfigHex
#include "docparse.h"     // lowerExtOf — the SHARED extension step (no third copy of the lowercase loop)
#include "arch.h"         // fnv1a64 — the cache trailer checksum and the repo key
#include "infra/jsonesc.h"      // shSingleQuote
#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace gitoracle
{

// ── tuning constants (every bound the probe rests on, in one place) ──────────────────────────────────────

// A shorter token is punctuation-adjacent noise ("i", "n", "ptr"), never a name a doc anchors a claim on.
// Matches docdrift::kMinMentionLen, so every name that lane can ASK about is a name this lane can ANSWER.
constexpr std::size_t   kMinNameLen     = 4;
constexpr std::size_t   kMaxNameLen     = 96;         // past this it is a minified blob, not an identifier
constexpr std::uint32_t kMaxProbeCommits = 40000;     // walk bound — past it, misses are "unknown", never "never"
constexpr std::size_t   kMaxProbeBytes  = 1u << 30;   // 1 GiB of patch text — the same bound, in the other unit
constexpr std::size_t   kMaxNamesTracked = 2000000;   // map bound; 44,904 on the deepest repo measured
constexpr std::size_t   kProbeChunk     = 1u << 20;   // patch-stream read granularity

// Bump when the CACHE BLOB FORMAT or the probe's semantics change: it is folded into the filename key, so an
// old-scheme blob is simply never named again (the qms/qsnap convention — no migration step, no stale read).
constexpr std::uint32_t kOracleCacheScheme = 1;

constexpr std::uint32_t kOracleCacheMagic  = 0x4f545843u;   // "CTXO" — a foreign blob can never be mistaken for ours

// ── the verdict vocabulary ───────────────────────────────────────────────────────────────────────────────
// The whole point of the oracle is that these three are DIFFERENT answers. Collapsing Never into Removed is
// the false positive doc-drift ships today; collapsing Unknown into Never would be a worse one, because it
// would sound like proof.

enum class Fate : std::uint8_t { Unknown = 0, Never, Removed };

struct FateSpec { const char* tag; const char* note; };

// Every note states a fact about HISTORY ALONE, and is therefore true whether or not HEAD happens to carry
// the name today. That phrasing is deliberate and was a bug first: an earlier table said "…and HEAD does not
// have it", which --whereis then printed verbatim underneath on-head="1" for a symbol that plainly existed.
// The oracle cannot see HEAD's tree, so it must not narrate it — the consumer joins the two facts.
inline constexpr FateSpec kFateTable[] = {
    { "unknown", "the history probe makes no claim for this name: either the walk hit its bound before reaching an answer, or the name is shorter than the minimum length the probe tracks" },
    { "never",   "no commit reachable from HEAD ever removed a line carrying this name — so for a name HEAD does not have, this repo never had it" },
    { "removed", "the newest commit reachable from HEAD that removed a line carrying this name — so for a name HEAD no longer has, that is when it left" },
};

static_assert( std::size( kFateTable ) == std::size_t( Fate::Removed ) + 1,
               "kFateTable drifted from the Fate enum — update both together" );

inline const char* fateTag( Fate f ) noexcept
{
    // A Fate reaching here out of range means a corrupt cache blob got past loadOracleCache's validation and
    // is about to index this table out of bounds — an invariant, not a recoverable input, so VERIFY (free in
    // release, and the ASan build turns the corrupt-blob fuzz in test/historyoraclecheck.sh into a real test
    // of that claim).
    VERIFY( std::size_t( f ) < std::size( kFateTable ) );
    return kFateTable[ std::size_t( f ) ].tag;
}

// Where and when one name left. `commit`/`date`/`path` are meaningful only for Fate::Removed.
struct NameFate
{
    Fate        fate = Fate::Unknown;
    std::string commit;     // full sha of the newest commit that removed a line carrying the name
    std::string date;       // that commit's COMMITTER date, YYYY-MM-DD (git's clock, never the wall clock)
    std::string path;       // the file the removal happened in — the evidence a reader spot-checks
};

// The whole-repo answer for one HEAD sha: every name history ever removed, plus the honesty flags.
struct HistoryIndex
{
    bool          ok         = false;   // false ⇒ no answer at all (not a git repo, git unavailable, probe failed)
    bool          nonGitRoot = false;
    bool          truncated  = false;   // hit kMaxProbeCommits / kMaxProbeBytes / kMaxNamesTracked ⇒ a miss is Unknown
    std::uint32_t commitsWalked = 0;
    std::string   headSha;

    // name → newest removal. Absent + !truncated ⇒ Fate::Never; absent + truncated ⇒ Fate::Unknown.
    HashMap<std::string, NameFate> removed;

    // The one accessor every consumer uses, so the absent-key rule lives in ONE place instead of at each
    // call site (where "absent means never" would sooner or later be written without the truncated guard).
    //
    // The LENGTH guard belongs here for the same reason. The walk only records identifiers of at least
    // kMinNameLen bytes, so a shorter name is absent from the map for a reason that has nothing to do with
    // history — and answering "never" for it would be a confident lie rather than a missing row. Both
    // consumers can hand this a short name (doc-drift admits a 2-char mention written with explicit parens),
    // so the choke point is the only place the rule cannot be forgotten.
    NameFate fateOf( const std::string& name ) const
    {
        if( !ok || name.size() < kMinNameLen || name.size() > kMaxNameLen )
        {
            return NameFate {}; // Unknown
        }
        const auto it = removed.find( name );
        if( it != removed.end() )
        {
            return it->second;
        }
        NameFate miss;
        miss.fate = truncated ? Fate::Unknown : Fate::Never;
        return miss;
    }
};

// ── identifier scanning over one removed line ────────────────────────────────────────────────────────────

inline bool identByte( unsigned char c ) noexcept { return std::isalnum( c ) || c == '_'; }

// Feed every identifier token of `line` to `onName`. Deliberately language-agnostic: the patch stream mixes
// every grammar in the tree (and several this tool does not parse), so a lexer per language would both cost
// more and see LESS than the one rule every one of them shares.
template<class OnName>
inline void forEachIdentifier( std::string_view line, OnName onName )
{
    for( std::size_t i = 0; i < line.size(); )
    {
        if( !( std::isalpha( (unsigned char)line[i] ) || line[i] == '_' ) ) { ++i; continue; }
        const std::size_t start = i;
        while( i < line.size() && identByte( (unsigned char)line[i] ) )
        {
            ++i;
        }
        const std::size_t len = i - start;
        if( len >= kMinNameLen && len <= kMaxNameLen )
        {
            onName( line.substr( start, len ) );
        }
    }
}

// A prose path contributes weaker evidence than a code path: a name deleted from a DOC only proves the doc
// changed. The probe records both, preferring a code site, so a "removed" row cites the code deletion when
// one exists (see recordRemoval below).
inline bool isProsePath( std::string_view path )
{
    const std::string ext = docparse::lowerExtOf( path );   // the shared extension step, not a third copy
    return ext == ".md" || ext == ".markdown" || ext == ".txt" || ext == ".rst";
}

// ── the cache blob (per repo, per HEAD sha) ──────────────────────────────────────────────────────────────
// Layout, all little-endian native (the blob never leaves this machine — the same assumption every other
// ripwire cache family makes):
//   u32 magic | u32 scheme | u8 truncated | u32 commitsWalked | u32 nameCount
//   nameCount x { u16 nameLen, bytes | u8 fate | u16 commitLen, bytes | u16 dateLen, bytes | u16 pathLen, bytes }
//   u64 fnv1a64 over every byte before it
// Three independent guards make a stale or foreign blob a clean MISS rather than a wrong answer: the magic,
// the scheme (folded into the filename too), and the trailing checksum.

inline std::string oracleExclHex()
{
    // exclConfigHex is the shared "hash a string vector + a scheme tag into 16 hex" body. This family has no
    // per-run configuration to key on — the answer depends only on (repo, HEAD sha) — so the vector is empty
    // and the scheme tag carries the whole field. Passing it through the shared helper anyway keeps this
    // family's filename shape identical to qms/qsnap/qbody rather than inventing a fourth spelling.
    return quality::exclConfigHex( {}, "qhist" + std::to_string( kOracleCacheScheme ) );
}

inline std::string oracleCachePath( const std::string& root, const std::string& headSha )
{
    return quality::shaKeyedCachePath( "qhist", quality::headSnapRepoHex( root ), oracleExclHex(), headSha );
}

// The fixed-width fields go through quality.h's own POD pair — quality::qsnapPut / quality::qsnapGet, the
// exact same two templates this family would otherwise have re-declared (they are named for the qsnap blob
// but are generic, and this header already includes quality.h for the cache-path convention). Only the
// length-prefixed STRING field below is new, because no existing family stores one.
using quality::qsnapGet;
using quality::qsnapPut;

inline void putStr( std::string& b, const std::string& s )
{
    // Every field written here is a git-controlled identifier / sha / date / path, all far inside 64 KiB; a
    // pathological one is CLAMPED rather than allowed to wrap the length field (G1 runs -fsanitize=integer).
    const std::uint16_t n = std::uint16_t( std::min<std::size_t>( s.size(), 0xffffu ) );
    qsnapPut( b, n );
    b.append( s.data(), n );
}

// A STICKY cursor over the blob: qsnapGet already does the bounds-checked POD read, but it reports failure
// per call, and a record here is a run of six reads whose first short one invalidates all the rest. `bad`
// latches so the caller checks ONCE per record instead of six times — a check it would eventually forget.
struct Reader
{
    const char* p   = nullptr;
    const char* end = nullptr;
    bool        bad = false;

    template<class T>
    T pod()
    {
        T v{};
        if( bad || !qsnapGet( p, end, v ) ) { bad = true; return T{}; }
        return v;
    }
    std::string str()
    {
        const std::uint16_t n = pod<std::uint16_t>();
        if( bad || std::size_t( end - p ) < n ) { bad = true; return {}; }
        std::string s( p, n );
        p += n;
        return s;
    }
};

inline bool saveOracleCache( const std::string& path, const HistoryIndex& idx )
{
    // Sorted, so the blob is a pure function of the index rather than of HashMap iteration order. The map is
    // never re-serialized in a different order, which is what keeps a cache byte-comparable between runs.
    std::vector<const std::string*> names;
    names.reserve( idx.removed.size() );
    for( const auto& [ name, fate ] : idx.removed ) { (void)fate; names.push_back( &name ); }
    std::sort( names.begin(), names.end(), []( const std::string* a, const std::string* b ) { return *a < *b; } );

    // The key list must be a permutation of the map, or the count written into the header below disagrees
    // with the records that follow it and every later read of this blob mis-frames — the silent-corruption
    // shape, which is exactly what a VERIFY is for.
    VERIFY( names.size() == idx.removed.size() );

    std::string body;
    body.reserve( names.size() * 72 + 32 );
    qsnapPut<std::uint32_t>( body, kOracleCacheMagic );
    qsnapPut<std::uint32_t>( body, kOracleCacheScheme );
    qsnapPut<std::uint8_t> ( body, idx.truncated ? 1u : 0u );
    qsnapPut<std::uint32_t>( body, idx.commitsWalked );
    qsnapPut<std::uint32_t>( body, std::uint32_t( names.size() ) );
    for( const std::string* n : names )
    {
        const NameFate& f = idx.removed.find( *n )->second;
        putStr( body, *n );
        qsnapPut<std::uint8_t>( body, std::uint8_t( f.fate ) );
        putStr( body, f.commit );
        putStr( body, f.date );
        putStr( body, f.path );
    }
    qsnapPut<std::uint64_t>( body, fnv1a64( body ) );

    // Write-then-rename: a reader in another process must never see a half-written blob (the torn-read rule
    // the rest of the cache families follow).
    const std::string tmp = path + ".tmp";
    std::FILE*        fp  = std::fopen( tmp.c_str(), "wb" );
    if( !fp )
    {
        DEGRADED_PATH_ALERT( "gitoracle: cannot write the history cache — the probe stays correct but re-runs cold" );
        return false;
    }
    const bool wrote = std::fwrite( body.data(), 1, body.size(), fp ) == body.size();
    std::fclose( fp );
    if( !wrote || std::rename( tmp.c_str(), path.c_str() ) != 0 )
    {
        std::remove( tmp.c_str() );
        DEGRADED_PATH_ALERT( "gitoracle: history cache write/rename failed — the probe stays correct but re-runs cold" );
        return false;
    }
    return true;
}

inline bool loadOracleCache( const std::string& path, HistoryIndex& idx )
{
    std::string bytes;
    {
        std::FILE* fp = std::fopen( path.c_str(), "rb" );
        if( !fp )
        {
            return false; // a plain miss, not a degrade
        }
        char        buf[ 65536 ];
        std::size_t n = 0;
        while( ( n = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
        {
            bytes.append( buf, n );
        }
        std::fclose( fp );
    }
    if( bytes.size() < sizeof( std::uint64_t ) + 17 )
    {
        return false;
    }

    const std::size_t payload = bytes.size() - sizeof( std::uint64_t );
    std::uint64_t     stored  = 0;
    std::memcpy( &stored, bytes.data() + payload, sizeof( stored ) );
    if( stored != fnv1a64( std::string_view( bytes.data(), payload ) ) )
    {
        return false; // corrupt/foreign — recompute
    }

    Reader r{ bytes.data(), bytes.data() + payload, false };
    if( r.pod<std::uint32_t>() != kOracleCacheMagic )
    {
        return false;
    }
    if( r.pod<std::uint32_t>() != kOracleCacheScheme )
    {
        return false;
    }

    HistoryIndex loaded;
    loaded.truncated     = r.pod<std::uint8_t>() != 0;
    loaded.commitsWalked = r.pod<std::uint32_t>();
    const std::uint32_t nameCount = r.pod<std::uint32_t>();
    if( r.bad || nameCount > kMaxNamesTracked )
    {
        return false;
    }

    loaded.removed.reserve( nameCount );
    for( std::uint32_t i = 0; i < nameCount; ++i )
    {
        std::string name = r.str();
        NameFate    f;
        f.fate   = Fate( r.pod<std::uint8_t>() );
        f.commit = r.str();
        f.date   = r.str();
        f.path   = r.str();
        // Validate every record before it enters the map: a bad read, a nameless entry, a fate outside the
        // table, or a Removed with no commit to name are all "this is not our blob" — a clean MISS that
        // recomputes, never a partially-trusted index. (This is also what keeps writeNameFate's VERIFY an
        // invariant rather than something a crafted cache file could trip; fuzzed in the gate.)
        if( r.bad || name.empty() || std::size_t( f.fate ) >= std::size( kFateTable ) )
        {
            return false;
        }
        if( f.fate == Fate::Removed && f.commit.empty() )
        {
            return false;
        }
        loaded.removed.emplace( std::move( name ), std::move( f ) );
    }
    if( r.bad || r.p != r.end )
    {
        return false; // trailing garbage ⇒ not our blob
    }

    loaded.ok = true;
    idx       = std::move( loaded );
    return true;
}

// ── the probe ────────────────────────────────────────────────────────────────────────────────────────────

// Where the walk currently is: the commit/date/file whose removed lines are being folded in right now. It
// travels as one value because it changes per HUNK while names change per TOKEN — bundling it also keeps
// recordRemoval at two arguments instead of the six the fields would otherwise spell out.
struct RemovalSite
{
    std::string commit;
    std::string date;
    std::string path;
    bool        isProse = false;   // derived from `path` whenever it is set — see RemovalSite::setPath

    void setPath( std::string_view p ) { path.assign( p ); isProse = isProsePath( path ); }
};

// Record one name's removal, newest-commit-first. Two slots collapse into one rule: the FIRST record wins
// (the walk is newest-first, so first == newest), except that a prose-only record is UPGRADED once by the
// first code-file record beneath it — a name deleted from CODE is the evidence a doc-drift row wants to
// cite, and citing a markdown deletion when a real one exists reads as weaker proof than the repo has.
inline void recordRemoval( HistoryIndex& idx, std::string_view name, const RemovalSite& site )
{
    // A removal with no commit to name is not evidence — it means a diff line arrived before any commit
    // header, i.e. a malformed stream. DEGRADE (drop the token), never record a Removed that cannot say
    // WHERE it was removed; downstream treats "Removed" as a claim backed by a sha, and VERIFYs as much.
    if( site.commit.empty() )
    {
        DEGRADED_PATH_ALERT( "gitoracle: a removed line arrived before any commit header — dropping it rather than recording an unattributed removal" );
        return;
    }

    const auto it = idx.removed.find( std::string( name ) );
    if( it == idx.removed.end() )
    {
        if( idx.removed.size() >= kMaxNamesTracked ) { idx.truncated = true; return; }
        NameFate f;
        f.fate   = Fate::Removed;
        f.commit = site.commit;
        f.date   = site.date;
        f.path   = site.path;
        idx.removed.emplace( std::string( name ), std::move( f ) );
        return;
    }
    if( site.isProse || !isProsePath( it->second.path ) )
    {
        return; // already the best evidence we will get
    }
    it->second.commit = site.commit;                                   // upgrade prose-site → code-site, once
    it->second.date   = site.date;
    it->second.path   = site.path;
}

// Fold ONE line of the patch stream into the index. This is the whole grammar the probe needs, and it is
// four cases in priority order — kept out of runProbe so the PARSING rules read as rules rather than as
// another nesting level inside the I/O loop.
inline void foldPatchLine( std::string_view raw, RemovalSite& site, HistoryIndex& idx )
{
    // 1) a commit header, framed by \x01 (which cannot occur in a unified-diff marker column)
    if( !raw.empty() && raw.front() == '\x01' )
    {
        const std::string_view rest = raw.substr( 1 );
        const std::size_t      sp   = rest.find( ' ' );
        site.commit.assign( sp == std::string_view::npos ? rest : rest.substr( 0, sp ) );
        site.date.assign  ( sp == std::string_view::npos ? std::string_view{} : rest.substr( sp + 1 ) );
        ++idx.commitsWalked;
        return;
    }

    // 2) "--- a/<path>" names the side removals come FROM, and 3) the other file headers are skipped. Both
    //    MUST be tested before the single-'-' test below, or every "---" header is read as a removed line.
    if( raw.size() > 6 && raw.compare( 0, 6, "--- a/" ) == 0 ) { site.setPath( raw.substr( 6 ) ); return; }
    if( raw.size() >= 3 && ( raw.compare( 0, 3, "---" ) == 0 || raw.compare( 0, 3, "+++" ) == 0 ) )
    {
        return;
    }

    // 4) a removed line: every identifier on it left the tree in `site`'s commit
    if( raw.empty() || raw.front() != '-' )
    {
        return;
    }
    forEachIdentifier( raw.substr( 1 ), [ & ]( std::string_view name ) { recordRemoval( idx, name, site ); } );
}

// ── the shared patch-stream reader ───────────────────────────────────────────────────────────────────────
// One hand-rolled line splitter over fixed-size reads: getline() would allocate per line, and this stream is
// a quarter of a gigabyte of them on the deepest repo measured (gitmine::gitCommandLines, which buffers every
// line into a vector, would hold all of that in RAM at once). `line` accumulates only the tail of a line that
// straddled a chunk boundary, so the common case never copies at all.
//
// TWO walkers share this reader now — the name-history oracle below, and renamemine.h's rename harvester —
// so the loop lives here once rather than being cloned into the second one. What the two do NOT share is the
// bound: each owns the counter it is folding into, so `keepWalking` is the caller's predicate. The BYTE bound
// is walker-independent and is enforced here.
struct PatchWalk
{
    bool        started   = false;   // popen succeeded; false ⇒ NO ANSWER, which is not the same as "nothing found"
    bool        truncated = false;   // a bound was hit ⇒ what was seen is true, what was not seen is UNKNOWN
    int         status    = 0;       // pclose status; non-zero ⇒ the walk cannot be assumed complete
    std::size_t bytesRead = 0;
};

template<class OnLine, class KeepWalking>
inline PatchWalk walkGitPatch( const std::string& cmd, OnLine onLine, KeepWalking keepWalking )
{
    PatchWalk  walk;
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return walk;                                          // the CALLER names the degrade — it knows what it lost
    }
    walk.started = true;

    std::string       line;
    std::vector<char> chunk( kProbeChunk );
    while( keepWalking() && walk.bytesRead < kMaxProbeBytes )
    {
        const std::size_t got = std::fread( chunk.data(), 1, chunk.size(), pipe );
        if( got == 0 )
        {
            break;
        }
        walk.bytesRead += got;

        std::size_t at = 0;
        while( at < got )
        {
            const void* nl = std::memchr( chunk.data() + at, '\n', got - at );
            if( !nl ) { line.append( chunk.data() + at, got - at ); break; }
            const std::size_t e = std::size_t( static_cast<const char*>( nl ) - chunk.data() );
            if( line.empty() )
            {
                onLine( std::string_view( chunk.data() + at, e - at ) );
            }
            else
            {
                line.append( chunk.data() + at, e - at );
                onLine( line );
                line.clear();
            }
            at = e + 1;
        }
    }
    if( !line.empty() )
    {
        onLine( line );
    }

    // A bound hit is not a failure — it is an answer of a different STRENGTH, and saying so is the whole
    // difference between this oracle and a guess. Drain rather than SIGPIPE git mid-write.
    if( !keepWalking() || walk.bytesRead >= kMaxProbeBytes )
    {
        walk.truncated = true;
        char sink[ 65536 ];
        while( std::fread( sink, 1, sizeof( sink ), pipe ) > 0 ) {}
    }
    walk.status = pclose( pipe );
    return walk;
}

// Walk `git log` newest-first and fold every removed line into `idx`. ONE process, ONE pass, whatever the
// number of names anyone will later ask about.
//
// The flag set is load-bearing, not decoration:
//   --no-merges   a merge's diff is not shown by default anyway; saying so keeps the walk honest and cheap
//                 (the LIMIT: a deletion performed ONLY as a merge resolution is invisible — documented).
//   -p -U0        the patch, with zero context lines: a CONTEXT line is unchanged content, and counting it
//                 as removed would make almost every name look deleted.
//   --no-renames  a rename becomes delete+add, which is what makes "newest removal" total (see the header).
//   --no-color / --no-ext-diff / --no-textconv
//                 the output must be plain unified diff whatever the user's git config says; an external
//                 differ or a textconv filter would both change the format and run someone else's program.
//   --format=%x01%H %cs
//                 a \x01-led header line per commit. \x01 cannot appear in a unified-diff marker column, so
//                 the framing is unambiguous without a second pass. %cs is git's COMMITTER date — the same
//                 deterministic clock quality::gitCommitterDateIso uses; the wall clock is never consulted.
inline HistoryIndex runProbe( const std::string& root )
{
    HistoryIndex idx;

    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " log --no-merges --no-color --no-ext-diff --no-textconv --no-renames"
                            " --format='%x01%H %cs' -p -U0 2>/dev/null";

    RemovalSite     site;
    const PatchWalk walk = walkGitPatch( cmd,
                                         [ & ]( std::string_view raw ) { foldPatchLine( raw, site, idx ); },
                                         [ & ] { return idx.commitsWalked <= kMaxProbeCommits; } );
    if( !walk.started )
    {
        DEGRADED_PATH_ALERT( "gitoracle: git log failed to start — the history probe answers unknown for every name" );
        return idx;
    }
    if( walk.truncated )
    {
        idx.truncated = true;
        DEGRADED_PATH_ALERT( "gitoracle: history walk hit its bound — names it did not see report unknown, never never" );
    }
    const int status = walk.status;

    // THE dangerous failure, and the reason it gets its own guard rather than riding on `ok = true`: the
    // caller has already established that HEAD resolves, so a walk that produced ZERO commit headers did not
    // find "a repo with no removals" — it found a git that failed (stderr is swallowed, so popen itself
    // succeeds and hands back an empty stream). An empty map with ok=true answers "never" for EVERY name,
    // confidently and wrongly, which is worse than the false positives this whole verb exists to remove.
    // Report NO ANSWER instead, so every name reads unknown.
    if( idx.commitsWalked == 0 )
    {
        DEGRADED_PATH_ALERT( "gitoracle: git log produced no commits despite a resolvable HEAD — reporting no answer rather than 'never' for every name" );
        return HistoryIndex{};
    }

    // A non-zero exit with commits already in hand is the weaker version of the same problem: what we read is
    // still true (a removal we SAW really happened), but the walk cannot be assumed complete, so a name we did
    // NOT see must not read as "never". That is exactly what `truncated` means — reuse it rather than throw
    // away a partial answer that is honest about being partial.
    if( status != 0 )
    {
        idx.truncated = true;
        DEGRADED_PATH_ALERT( "gitoracle: git log exited non-zero mid-walk — the answer is kept but marked truncated, so unseen names report unknown" );
    }

    idx.ok = true;
    return idx;
}

// The memoized entry point. `root` must be the repo root; a non-git root (or one with no commits) comes back
// ok=false + nonGitRoot=true so the caller can say so instead of silently answering "never" for everything.
inline HistoryIndex probeNameHistory( const std::string& root )
{
    HistoryIndex idx;
    if( !quality::gitRepoHasHistory( root ) ) { idx.nonGitRoot = true; return idx; }

    idx.headSha = quality::gitHeadSha( root );
    if( idx.headSha.empty() ) { idx.nonGitRoot = true; return idx; }

    const std::string cachePath = oracleCachePath( root, idx.headSha );
    {
        HistoryIndex warm;
        if( loadOracleCache( cachePath, warm ) )
        {
            warm.headSha = idx.headSha;
            return warm;                                               // byte-identical to the cold answer, by test
        }
    }

    HistoryIndex fresh = runProbe( root );
    fresh.headSha      = idx.headSha;
    if( fresh.ok )
    {
        saveOracleCache( cachePath, fresh );
    }
    return fresh;
}

// ── shared XML emission ──────────────────────────────────────────────────────────────────────────────────
// Both consumers print the same evidence in the same shape, so the shape lives here once. G4: an XML comment
// may not contain a double hyphen, so flag names are written WITHOUT their leading dashes.

// The `<history .../>` element a verb emits to state what the probe did (or why it did nothing). `escape` is
// the caller's own escaper, so this header needs no dependency on serialize.h's buffer discipline.
template<class Escape>
inline void writeHistoryProbe( std::FILE* out, const HistoryIndex& idx, Escape escape )
{
    if( !idx.ok )
    {
        std::fprintf( out, "<history probed=\"0\" r=\"%s\"/>",
                      idx.nonGitRoot ? "not-a-git-repo" : "probe-failed" );
        return;
    }
    std::fprintf( out, "<history probed=\"1\" head=\"%.9s\" commits=\"%u\" removed-names=\"%zu\"%s/>",
                  idx.headSha.c_str(), idx.commitsWalked, idx.removed.size(),
                  idx.truncated ? " truncated=\"1\"" : "" );
    (void)escape;
}

// One name's verdict, as the `<fate .../>` element --whereis emits.
template<class Escape>
inline void writeNameFate( std::FILE* out, const std::string& name, const NameFate& f, Escape escape )
{
    // Fate::Removed is a claim about a specific commit, so the commit must be there to name. A Removed with
    // no sha would print `commit=""` and read as evidence while carrying none.
    VERIFY( f.fate != Fate::Removed || !f.commit.empty() );

    std::fprintf( out, "<fate sym=\"%s\" v=\"%s\"", escape( name ).c_str(), fateTag( f.fate ) );
    if( f.fate == Fate::Removed )
    {
        std::fprintf( out, " commit=\"%.9s\" date=\"%s\" p=\"%s\"",
                      f.commit.c_str(), escape( f.date ).c_str(), escape( f.path ).c_str() );
    }
    std::fprintf( out, " note=\"%s\"/>", escape( kFateTable[ std::size_t( f.fate ) ].note ).c_str() );
}

}}   // namespace rw::gitoracle
