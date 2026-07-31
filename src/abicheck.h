#pragma once

// abicheck.h — `--stray-content --abi`: the cross-branch ABI-BREAK gate neither verb alone can see.
//
// `--layout=STRUCT` computes one struct's field offsets/size and diffs every same-name definition — but it
// only ever looks at ONE index, the working tree. `--stray-content` sweeps every branch's blobs for content
// the live line lacks — but it is LINE-granular: "added a float field" is just a stray line to it. A branch
// that adds one field to a dual-compile uniform struct merges TEXTUALLY clean (git sees no conflict), review
// sees a harmless "+1 field", and the CPU ends up writing more bytes than the GPU reads for — wrong pixels,
// no compiler error, nothing either existing verb's report would flag on its own.
//
// This file answers the composed question directly: for every struct a ref's OWN WORK changed, does that
// ref's copy compute to a DIFFERENT size or field offset than HEAD's? Pure composition, per the same
// reasoning flipimpact.h documents for its own split:
//   the struct model         — layout.h's modelDefFromSource / findDefBody / diffDefs, reused VERBATIM
//   the ref/blob sweep        — crossref.h's enumerateRefs / diffRaw / streamBlobs, reused VERBATIM
// The one new primitive is layout.h's findTopLevelDef() — the lexical "find this aggregate's body with no
// index" a ref's blob needs, since it was never ingested (added there, not here, because it is a natural
// extra ENTRY POINT into the existing offset model, not a git concern).
//
// ── AUTHORSHIP is the whole ballgame (the r25 correction) ────────────────────────────────────────────────
// The first cut of this file swept `diff HEAD..tip`, which answers a question nobody asked: "does this
// branch's copy of every struct differ from the live line's?" On a long-lived shared tree the answer is
// yes, constantly — because HEAD moved, not because the branch did anything. Measured on a 35-branch C++
// repo: 487 kind="drift" rows, of which 9 lay on a path the branch had ever touched — and of those, 4
// survived the per-STRUCT authorship test below. The other 483 were the live line's own evolution
// reflected back at the reader.
//
// (Formatting note, learned the hard way here: this file's XML prose goes through fprintf, so a literal
// percent sign in it is a CONVERSION, not a character — one "98% of the rows" made the output
// non-deterministic run to run. Spell percentages out as counts, or escape them.)
//
// So the sweep is anchored at each ref's MERGE BASE, exactly the discipline crossref.h's §1 already had to
// derive for stray LINES ("stray content must be lines the branch AUTHORED"), lifted to struct SHAPES:
//   scope   — the paths `diff base..tip` reports, not `diff HEAD..tip`. A file the branch never opened
//             cannot be a break it introduced; git will take HEAD's copy at merge time.
//   verdict — a struct whose ref-side shape is IDENTICAL to its own merge-base shape is kind="head-moved":
//             the difference against HEAD is real, and the branch did not author it. Counted, not listed.
// Paths only the LIVE LINE changed are counted too (head_only=), so the narrowing is a number on the header
// rather than a silent filter.
//
// ── the cost model ────────────────────────────────────────────────────────────────────────────────────────
// HEAD's side is FREE: every candidate struct is already modelled once (memoized) off the SAME on-disk
// bytes --layout itself reads, via the SAME modelDef() call. The ref side follows crossref's own economy —
// two shared `git diff --raw` per ref (base..tip for scope, base..HEAD for the head_only counter, the
// latter memoized per merge-base sha), one shared `git cat-file --batch` for the whole sweep, each distinct
// blob reduced exactly once no matter how many refs (or how many candidate structs in one file) point at
// it. Raw blob bytes are consumed inside the streaming callback and never retained past it — same
// discipline as crossref.h's own BlobStore, just reducing to a LayoutDef instead of a BlobFacts. Anchoring
// at the merge base makes the sweep CHEAPER as well as truer: the blob set shrinks with the path set.
//
// ── what "candidate" means, and the LIMIT that follows from it ──────────────────────────────────────────
// A candidate is every C-family struct/class HEAD's index declares, in the SAME file it is declared in
// (layout.h's own isCFamilyPath filter — a TypeScript/Swift class is not a byte layout). A struct whose
// HEAD-side copy this module cannot model at all (pragma pack, bitfields, a base class, ...) carries no
// baseline to diff against, so it is not attempted — candidates= counts what HEAD declares and
// unmodelable= counts the ones skipped for want of a baseline, making that omission auditable rather than
// silent.
//
// ── the honesty contract, inherited (not respelled) ──────────────────────────────────────────────────────
// layout.h already refuses to print a plausible wrong number: modeled="0" plus a named caveat beats a lie.
// This module inherits that AT THE REF SIDE too — a ref whose copy of the struct cannot be modelled reports
// kind="unknown", never "same", and its caveats ride along in <ref_caveat> exactly as layout.h recorded
// them. The vocabulary, and which half of it the default view LISTS (see kKindPolicy — one table, one
// place):
//   same       — quiet, the common case: not reported as a <struct> row at all (report only DIFFERENCES).
//   drift      — the BYTE contract differs. The bug this file exists for; the only kind that exits 2.
//   unknown    — the ref-side copy could not be modelled; see its <ref_caveat> rows. Never "same".
//   absent     — the ref does not define the struct at that path at all: deleted, binary/oversized, or a
//                lexical miss (see findTopLevelDef's own LIMIT — a struct nested in a class or wrapped in
//                `extern "C"` is not found even though --layout finds it fine on HEAD's indexed side).
//   rename     — same size, same positional slots, same field TYPES, different field NAMES. The bytes are
//                where they were; only the source spelling moved. Not a byte-contract break.
//   spelling   — identical bytes, different type NAMES — the two arms of one #ifdef block. Not a break.
//   stub       — one side is an empty placeholder aggregate (a test's stub_includes tree). Not a break.
//   head-moved — the ref's copy equals its own MERGE-BASE copy; the live line is what changed. Not the
//                branch's break.
// The first four LIST by default (the byte contract might differ, or cannot be certified); the last four
// are provably not a byte change the branch made, so they are COUNTED on the header and on their ref, and
// printed only under --detail=N. Nothing is dropped without a number.
//
// ── three approximations, named rather than hidden ───────────────────────────────────────────────────────
// (1) HEAD's own side is the WORKING TREE's current --layout answer (disk bytes), not a re-fetched git blob
//     at HEAD's commit — the exact same scope --layout's own doc comment already claims ("it only ever sees
//     one index — the working tree"). A dirty working tree means HEAD's row here is "right now", not the
//     last commit.
// (2) A field whose type is a NESTED aggregate (e.g. a `Pulse pulses[8]` member) sizes that nested type
//     through ctx's own HEAD-side index/disk cache, never the ref's blob — so a ref that changes BOTH a
//     struct and one of its nested member types in the same commit is scored against HEAD's copy of the
//     nested type, not the ref's. Rare (the motivating bug is a direct field add), and named here so it is
//     a documented trade rather than a silent one.
// (3) The authorship anchor is PER PATH and PER STRUCT, so the one hazard it cannot see is a CROSS-FILE
//     one: the branch changes struct S in file A while the live line changes S's mirror in file B, and the
//     merge fuses the two. `--layout=S` on the merge result is the verb for that; this one is per-path.
//
// Determinism: refs come from crossref::enumerateRefs (sorted by name already); candidates per path are
// sorted by name; blobs are visited in sha order (crossref::streamBlobs' own contract); every emitted list
// is re-sorted by an explicit key. No wall clock, no address hashing.

#include "model.h"
#include "layout.h"        // the offset model: modelDefFromSource / findDefBody / findTopLevelDef / diffDefs
#include "crossref.h"       // the ref/blob sweep: enumerateRefs / diffRaw / streamBlobs / isBlobSha / isNullSha
#include "quality.h"        // gitRepoHasHistory / gitHeadSha / gitOneLine
#include "arch.h"           // relForHash — ing.files' root-prefixed path -> the git-relative spelling diffRaw reports
#include "jsonesc.h"        // shSingleQuote — the merge-base call
#include "serialize.h"      // escapeXml
#include "Diagnostics.h"    // VERIFY / DEGRADED_PATH_ALERT

#include "btree.hpp"        // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cstdio>
#include <functional>
#include <numeric>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ctx
{
namespace abicheck
{

constexpr std::size_t kMaxStructsPerRef = 12;   // display cap per ref (mirrors crossref::kStrayFilesPerRef); --detail lifts it

// ── the kind vocabulary as ONE declarative table ─────────────────────────────────────────────────────────
// Three facts per kind — its tag, whether the DEFAULT view lists it, and whether it is a BREAK — in one
// place, so "which kinds are noise?" is a data question and the header counters, the body filter, the sort
// order and the exit code all read the same row. House rule: a table, not four scattered switches.

struct KindPolicy
{
    const char* tag;
    bool        listed;      // printed in the default body (false ⇒ counted on the header + its ref, hidden)
    bool        isBreak;     // contributes to broken_refs= and to exit 2
};

constexpr KindPolicy kKindPolicy[] =
{
    { "drift",      true,  true  },   // the byte contract differs, and this branch made it differ
    { "unknown",    true,  false },   // cannot be certified either way — never silently "same"
    { "absent",     true,  false },   // the branch's copy of this path does not declare it
    { "rename",     false, false },   // same slots, same types, different field names
    { "spelling",   false, false },   // same bytes, different type spellings (the ifdef arms)
    { "stub",       false, false },   // one side is an empty placeholder aggregate
    { "head-moved", false, false },   // the ref matches its own merge base; the live line moved
};
constexpr std::size_t kKindCount = sizeof( kKindPolicy ) / sizeof( kKindPolicy[0] );

// A pointer-to-member is the whole reason the table exists: "which kinds are listed?" and "which are
// breaks?" are the SAME walk over kKindPolicy with a different column selected, so they are one function
// each here rather than a copy per column.
using KindFlag = bool KindPolicy::*;

inline std::size_t kindIndex( std::string_view tag ) noexcept
{
    for( std::size_t i = 0; i < kKindCount; ++i ) if( tag == kKindPolicy[i].tag ) return i;
    return kKindCount;                                        // caller VERIFYs; no kind reaches here unnamed
}

inline bool kindFlag  ( std::string_view tag, KindFlag col ) noexcept { const std::size_t i = kindIndex( tag ); return i < kKindCount && kKindPolicy[i].*col; }
inline bool kindListed ( std::string_view tag ) noexcept { return kindFlag( tag, &KindPolicy::listed ); }
inline bool kindIsBreak( std::string_view tag ) noexcept { return kindFlag( tag, &KindPolicy::isBreak ); }

// Row tallies by kind. Every classified row lands in exactly one bucket, so total() is the count of rows
// the sweep produced and nothing can leave the pipeline without a number attached to it.
struct KindCounts
{
    std::uint32_t n[ kKindCount ] = {};

    void add( std::string_view tag ) noexcept
    {
        const std::size_t i = kindIndex( tag );
        VERIFY( i < kKindCount );
        if( i < kKindCount ) ++n[i];
    }
    std::uint32_t sumWhere( KindFlag col ) const noexcept
    {
        std::uint32_t t = 0;
        for( std::size_t i = 0; i < kKindCount; ++i ) if( kKindPolicy[i].*col ) t += n[i];
        return t;
    }
    std::uint32_t total()    const noexcept { return std::accumulate( std::begin( n ), std::end( n ), std::uint32_t( 0 ) ); }
    std::uint32_t listed()   const noexcept { return sumWhere( &KindPolicy::listed ); }
    std::uint32_t breaks()   const noexcept { return sumWhere( &KindPolicy::isBreak ); }
    std::uint32_t excluded() const noexcept { return total() - listed(); }
};

// ── the result model ─────────────────────────────────────────────────────────────────────────────────────

// One struct's verdict on ONE ref, relative to HEAD's --layout-computed model of the SAME (path, name).
struct StructRow
{
    std::string   name;
    std::string   path;               // the labeled path, exactly as ing.files spells it
    std::uint32_t headLine  = 0;
    const char*   kind      = "drift";// one of kKindPolicy's tags — see the file doc comment
    std::uint32_t headSize  = 0;
    std::uint32_t refSize   = 0;      // meaningful only when refSized — omitted from the XML otherwise
    std::uint32_t sizeDelta = 0;      // |headSize - refSize| when both are sized; the display RANK key
    bool          refSized  = false;  // the ref side produced a real number (not absent, not unmodellable)
    bool          sizeDiffers = false;
    std::vector<layout::FieldDiff> fields;
    std::vector<layout::Caveat>    headCaveats;   // usually empty (HEAD must already be modelled to reach here)
    std::vector<layout::Caveat>    refCaveats;    // the honesty requirement: inherited, never dropped
};

struct RefRow
{
    crossref::RefInfo      ref;
    std::string            base;              // merge-base(ref, HEAD) — the authorship anchor
    std::vector<StructRow> structs;           // every non-"same" row, listed and excluded alike
    KindCounts             counts;
    std::uint32_t          headOnly    = 0;   // candidate sites on paths only the LIVE LINE changed
    std::uint32_t          unmodelable = 0;   // candidate sites skipped: HEAD's own copy has no model
};

struct AbiResult
{
    bool           ok          = true;
    bool           nonGitRoot  = false;
    bool           tooManyRefs = false;
    std::string    headSha;
    std::string    headRef;
    std::size_t    refsScanned = 0;
    std::size_t    distinctBlobs = 0;
    std::size_t    candidates  = 0;   // (path,name) pairs HEAD declares and this module can LOCATE a body for
    std::size_t    compared    = 0;   // …of those, the (ref,path,name) sites actually modelled on both sides
    std::size_t    unmodelable = 0;   // sites skipped because HEAD's own copy carries no baseline to diff
    std::size_t    headOnly    = 0;   // candidate sites on paths only the live line changed (outside scope)
    std::uint32_t  unrelated   = 0;   // refs with no merge-base at all (unrelated history) — skipped, counted
    std::uint32_t  quietRefs   = 0;   // scanned, nothing to LIST — omitted from the body, counted here
    KindCounts     counts;            // every classified row, by kind, across every ref
    std::vector<RefRow> refs;         // only refs with >=1 LISTED struct row
};

// The verb's own verdict: only a real byte-contract DRIFT the branch AUTHORED is a break. Every other kind
// is a report, not a gate — exactly layout::layoutContractBroken's reasoning, restated for the cross-ref case.
inline bool abiContractBroken( const AbiResult& r ) noexcept
{
    for( const RefRow& rr : r.refs ) if( rr.counts.breaks() > 0 ) return true;
    return false;
}

// ── HEAD-side candidates ─────────────────────────────────────────────────────────────────────────────────

// One HEAD-declared struct this module can locate a body for, keyed by the path it lives in. `site` already
// carries fileId (set below), so this is everything modelDef() needs — nothing here reads a ref's blob.
struct Candidate
{
    std::string     name;
    layout::DefSite site;
};

// path -> its candidates, built ONCE from HEAD's index. The inverse cut of computeLayout's own symbol walk
// ("every def of THIS name") — this needs "every modelable def in THIS file" — over the exact same data
// (ing.symbols, isCFamilyPath, findDefBody), with the SAME (fileId,braceStart) dedupe that drops a struct's
// own typedef-alias twin.
//
// Keyed by the ROOT-RELATIVE path (arch.h::relForHash), not ing.files' own `<ingest-root>/<relative>`
// spelling: `git diff --raw` reports paths relative to the repo root, and every ing.files entry carries the
// ingest root prefix verbatim (an absolute root gives an absolute path). Without this the two path spellings
// never collide and every candidate silently goes unmatched — found by running this against a real repo, not
// by inspection, exactly the S2 trap relForHash's own comment names.
inline gtl::btree_map<std::string, std::vector<Candidate>> buildCandidates( layout::ModelCtx& ctx, std::string_view root )
{
    gtl::btree_map<std::string, std::vector<Candidate>> byPath;
    gtl::btree_map<std::uint64_t, bool>                  seenSite;

    for( const Symbol& s : ctx.ing.symbols )
    {
        if( s.kind != SymKind::Struct && s.kind != SymKind::Class && s.kind != SymKind::Interface ) continue;
        if( !layout::isCFamilyPath( ctx.ing.files[ s.fileId ] ) ) continue;

        const std::string& src = layout::fileBytes( ctx, s.fileId );
        if( src.empty() ) continue;

        layout::DefSite site;
        if( !layout::findDefBody( src, s.name, s.sigStartByte, site ) ) continue;
        site.fileId = s.fileId;

        const std::uint64_t key = ( std::uint64_t( s.fileId ) << 32 ) | std::uint64_t( site.braceStart & 0xFFFFFFFFull );
        if( seenSite.find( key ) != seenSite.end() ) continue;
        seenSite.emplace( key, true );

        const std::string relPath( relForHash( ctx.ing.files[ s.fileId ], root ) );
        byPath[ relPath ].push_back( Candidate{ s.name, site } );
    }
    for( auto& [ path, cands ] : byPath )
        std::sort( cands.begin(), cands.end(), []( const Candidate& a, const Candidate& b ) { return a.name < b.name; } );
    return byPath;
}

// HEAD's own model of one candidate, memoized by (fileId, braceStart) so N refs sharing a path cost ONE
// modelDef() call, not N — the same "read once, fan out" economy the ref side gets from streamBlobs.
inline const layout::LayoutDef& headDefFor( layout::ModelCtx& ctx, const Candidate& c,
                                            gtl::btree_map<std::uint64_t, layout::LayoutDef>& cache )
{
    const std::uint64_t key = ( std::uint64_t( c.site.fileId ) << 32 ) | std::uint64_t( c.site.braceStart & 0xFFFFFFFFull );
    const auto           it = cache.find( key );
    if( it != cache.end() ) return it->second;
    return cache.emplace( key, layout::modelDef( ctx, c.site.fileId, c.site, c.name ) ).first->second;
}

// ── the ref-side model store ─────────────────────────────────────────────────────────────────────────────

// One candidate's model as read out of ONE git blob. `present=false` means the lexical locator did not find
// the aggregate in those bytes at all (deleted / renamed away / nested out of file scope / binary blob).
struct DefSlot
{
    bool              present = false;
    layout::LayoutDef def;
};

// A (blob sha, path) pair models exactly one vector of DefSlots — parallel to byPath[path]'s candidate list,
// so a slot is addressed by candidate INDEX. Two refs pointing at the same blob, and the base/tip sides of
// one ref that happen to share a blob, all collapse onto one entry.
inline std::string modelKey( std::string_view sha, std::string_view path )
{
    std::string k( sha );
    k += '\n';
    k += path;
    return k;
}

// One (ref, candidate-bearing path the ref's own work changed). Both sides' blob shas ride along, so the
// classify pass can ask the authorship question ("is the ref's copy just its base's copy?") with no second
// git round trip.
struct PathSite
{
    std::uint32_t refIndex = 0;
    std::string   path;
    std::string   baseSha;      // the merge-base side
    std::string   tipSha;       // the ref side
};

using PathIndex = gtl::btree_map<std::string, std::vector<Candidate>>;
using HeadCache = gtl::btree_map<std::uint64_t, layout::LayoutDef>;

// The two accumulators every pass writes into: the per-ref rows (indexed by ref) and the whole-sweep header
// counters. One reference instead of two on every signature, and it names what a pass is allowed to mutate.
struct Tally
{
    std::vector<RefRow>& rows;
    AbiResult&           result;
};

// The read-mostly model context a classification needs: the offset model, HEAD's memo, and the counters.
struct ClassifyCtx
{
    layout::ModelCtx& ctx;
    HeadCache&        headCache;
    AbiResult&        result;
};

// One candidate as it stands on the two sides of ONE ref: its merge base and its tip. Either may be null
// (the blob was never fetched) or present=false (the locator found no such aggregate in those bytes).
struct RefSides
{
    const DefSlot* base = nullptr;
    const DefSlot* tip  = nullptr;
};

// The working set the three passes below hand to each other: WHERE to look (pathSites), WHICH blobs that
// needs (shaPaths), and the models read out of them (models). Bundled so each pass takes one reference
// rather than a six-parameter list.
struct SweepState
{
    std::vector<PathSite>                                 pathSites;
    gtl::btree_map<std::string, std::vector<std::string>> shaPaths;   // blob sha -> the paths to model it at
    gtl::btree_map<std::string, std::vector<DefSlot>>     models;     // modelKey(sha,path) -> per-candidate slots

    // Register a blob for the streaming batch. A missing/null/malformed sha is NOT an error — it simply
    // leaves every slot present=false, which the classifier reads as "absent on that side".
    void wantBlob( const std::string& sha, const std::string& path, std::size_t candCount )
    {
        if( sha.empty() || crossref::isNullSha( sha ) || !crossref::isBlobSha( sha ) ) return;
        const std::string key = modelKey( sha, path );
        if( models.find( key ) != models.end() ) return;
        models.emplace( key, std::vector<DefSlot>( candCount ) );
        shaPaths[ sha ].push_back( path );
    }
};

// ── pass 1: scope — the paths each ref's OWN work touched, anchored at its merge base ────────────────────

// `diff base..HEAD` restricted to candidate paths, memoized per merge-base sha — several refs off one base
// share the answer, and it is only ever read as a COUNT (the head_only= honesty number, never a verdict).
using PathMemo = gtl::btree_map<std::string, std::vector<std::string>>;

inline const std::vector<std::string>& headChangedPaths( const std::string& root, const std::string& headSha,
                                                         const std::string& base, const PathIndex& byPath, PathMemo& memo )
{
    auto hit = memo.find( base );
    if( hit != memo.end() ) return hit->second;

    std::vector<std::string> paths;
    for( const crossref::RawRow& r : crossref::diffRaw( root, base, headSha ) )
    {
        if( r.aSha == r.bSha )                      continue;
        if( byPath.find( r.path ) == byPath.end() )  continue;
        paths.push_back( r.path );
    }
    return memo.emplace( base, std::move( paths ) ).first->second;
}

inline void collectAuthoredSites( const std::string& root, const std::vector<crossref::RefInfo>& refs,
                                  const PathIndex& byPath, SweepState& sw, Tally tally )
{
    std::vector<RefRow>& rows   = tally.rows;
    AbiResult&           result = tally.result;
    PathMemo             headPathsByBase;

    for( std::uint32_t i = 0; i < refs.size(); ++i )
    {
        const std::string base = quality::gitOneLine( root, "merge-base " + shSingleQuote( refs[i].tip ) + " "
                                                          + shSingleQuote( result.headSha ) + " 2>/dev/null" );
        if( base.empty() )
        {
            DEGRADED_PATH_ALERT( "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );
            ++result.unrelated;
            continue;
        }
        rows[i].base = base;

        gtl::btree_map<std::string, bool> authoredPaths;
        for( const crossref::RawRow& r : crossref::diffRaw( root, base, refs[i].tip ) )
        {
            if( r.aSha == r.bSha )                      continue;   // mode-only change; content is identical
            const auto pit = byPath.find( r.path );
            if( pit == byPath.end() )                   continue;   // HEAD declares no locatable struct here
            authoredPaths.emplace( r.path, true );
            sw.pathSites.push_back( PathSite{ i, r.path, r.aSha, r.bSha } );
            sw.wantBlob( r.aSha, r.path, pit->second.size() );
            sw.wantBlob( r.bSha, r.path, pit->second.size() );
        }

        // Everything the narrowing dropped, as a number. A candidate site on a path the LIVE LINE changed
        // and this ref did not is outside the authored scope by construction — never a break this branch
        // introduced — but it is counted here rather than vanishing.
        for( const std::string& p : headChangedPaths( root, result.headSha, base, byPath, headPathsByBase ) )
        {
            if( authoredPaths.find( p ) != authoredPaths.end() ) continue;
            const auto pit = byPath.find( p );
            if( pit == byPath.end() ) continue;
            rows[i].headOnly += std::uint32_t( pit->second.size() );
        }
        result.headOnly += rows[i].headOnly;
    }
}

// ── pass 2: one shared streaming batch over every blob either side needs ─────────────────────────────────

inline void modelRefBlobs( const std::string& root, layout::ModelCtx& ctx, const PathIndex& byPath,
                           SweepState& sw, AbiResult& result )
{
    std::vector<std::string> shas;
    shas.reserve( sw.shaPaths.size() );
    for( const auto& [ sha, paths ] : sw.shaPaths ) { (void)paths; shas.push_back( sha ); }
    result.distinctBlobs = shas.size();

    crossref::streamBlobs( root, shas, [ & ]( const std::string& sha, std::string_view bytes, bool isText )
    {
        const auto sit = sw.shaPaths.find( sha );
        if( sit == sw.shaPaths.end() ) return;
        if( !isText ) return;                          // binary/oversized: every slot stays present=false

        // The comment-strip + constant harvest is per BLOB, not per (path,candidate) — several candidate
        // structs in the same file share one pass, same as layout.h's own per-file cache.
        const std::string        stripped = layout::withoutComments( bytes );
        const layout::ConstTable consts   = layout::harvestConstants( stripped );

        for( const std::string& path : sit->second )
        {
            const auto pit = byPath.find( path );
            const auto mit = sw.models.find( modelKey( sha, path ) );
            if( pit == byPath.end() || mit == sw.models.end() ) continue;
            VERIFY( mit->second.size() == pit->second.size() );

            for( std::size_t ci = 0; ci < pit->second.size() && ci < mit->second.size(); ++ci )
            {
                const Candidate& c = pit->second[ ci ];
                layout::DefSite  refSite;
                if( !layout::findTopLevelDef( bytes, c.name, refSite ) ) continue;   // absent in these bytes
                mit->second[ ci ].def     = layout::modelDefFromSource( ctx, bytes, stripped, consts, c.site.fileId, refSite, c.name );
                mit->second[ ci ].present = true;
            }
        }
    } );
}

// ── pass 3: classify one (ref, path) site's candidates ───────────────────────────────────────────────────

// The kind ONE candidate earns on ONE site, plus the row that carries the evidence for it. Split out of the
// loop so the verdict ladder — authorship, then presence, then modelability, then the byte comparison — is
// one readable expression instead of a nested branch inside a nested loop.
inline void classifyCandidate( ClassifyCtx cc, const Candidate& c, const PathSite& ps, RefSides sides, RefRow& rr )
{
    AbiResult&               result  = cc.result;
    const DefSlot*           tip     = sides.tip;
    const DefSlot*           base    = sides.base;
    const layout::LayoutDef& headDef = headDefFor( cc.ctx, c, cc.headCache );
    if( !headDef.modeled ) { ++rr.unmodelable; ++result.unmodelable; return; }   // no baseline to diff against
    ++result.compared;

    const bool tipPresent  = tip  != nullptr && tip->present;
    const bool basePresent = base != nullptr && base->present;
    if( tipPresent && tip->def.spellShape == headDef.spellShape ) return;        // matches HEAD: quiet

    StructRow srow;
    srow.name        = c.name;
    srow.path        = ps.path;
    srow.headLine    = headDef.line;
    srow.headSize    = headDef.size;
    srow.headCaveats = headDef.caveats;
    if( tipPresent )
    {
        srow.refCaveats = tip->def.caveats;
        srow.refSized   = tip->def.modeled;
        srow.refSize    = tip->def.size;
    }

    // AUTHORSHIP first: a ref-side copy byte- and spelling-identical to its own merge-base copy is not this
    // branch's doing, however loudly it disagrees with HEAD. Both-absent counts too — the live line ADDED
    // the struct, and the branch simply predates it.
    const bool sameAsBase = ( tipPresent == basePresent )
                         && ( !tipPresent || tip->def.spellShape == base->def.spellShape );

    // The field-by-field diff against HEAD is worth SHOWING whatever the verdict turns out to be — a
    // head-moved row under --detail is exactly "what did the live line do to this struct?" — so it is
    // computed once here and the verdict is decided after it.
    const char* shapeKind = "drift";
    if( srow.refSized )
    {
        const layout::MirrorDiff diff = layout::diffDefs( headDef, tip->def );
        shapeKind   = diff.kind;               // "drift" | "spelling" | "stub" — layout.h's own vocabulary
        srow.fields = diff.fields;

        // A RENAME is not a resize. Identical positional slots AND identical field TYPES with a different
        // field NAME leaves every byte where it was, so it cannot break a CPU/GPU buffer — layout.h's
        // byteShape folds the NAME in, which is what made this read as drift.
        // HONEST LIMIT: a same-TYPE field REORDER is lexically indistinguishable from a rename (both are
        // "these slots, different names") and lands here too. It is listed under --detail with its field
        // diff, never silently merged into "same".
        if( std::string_view( shapeKind ) == "drift" && headDef.slotShape == tip->def.slotShape )
            shapeKind = "rename";

        srow.sizeDiffers = srow.headSize != srow.refSize;
        srow.sizeDelta   = ( srow.headSize > srow.refSize ) ? srow.headSize - srow.refSize
                                                            : srow.refSize - srow.headSize;
    }

    if( sameAsBase )              srow.kind = "head-moved";
    else if( !tipPresent )        srow.kind = "absent";
    else if( !tip->def.modeled )  srow.kind = "unknown";                         // NEVER "same"
    else                          srow.kind = shapeKind;

    rr.counts.add( srow.kind );
    result.counts.add( srow.kind );
    rr.structs.push_back( std::move( srow ) );
}

inline void classifyPathSite( ClassifyCtx cc, const PathIndex& byPath, const SweepState& sw,
                              const PathSite& ps, RefRow& rr )
{
    const auto pit = byPath.find( ps.path );
    if( pit == byPath.end() ) return;
    const auto tipIt  = sw.models.find( modelKey( ps.tipSha,  ps.path ) );
    const auto baseIt = sw.models.find( modelKey( ps.baseSha, ps.path ) );

    for( std::size_t ci = 0; ci < pit->second.size(); ++ci )
    {
        RefSides sides;
        if( tipIt  != sw.models.end() && ci < tipIt->second.size()  ) sides.tip  = &tipIt->second[ ci ];
        if( baseIt != sw.models.end() && ci < baseIt->second.size() ) sides.base = &baseIt->second[ ci ];
        classifyCandidate( cc, pit->second[ ci ], ps, sides, rr );
    }
}

// ── the whole computation ────────────────────────────────────────────────────────────────────────────────

inline AbiResult computeAbiCheck( const std::string& root, const IngestResult& ing, std::string_view filter )
{
    AbiResult result;
    if( !quality::gitRepoHasHistory( root ) ) { result.ok = false; result.nonGitRoot = true; return result; }

    result.headSha = quality::gitHeadSha( root );
    result.headRef = quality::gitOneLine( root, "rev-parse --abbrev-ref HEAD 2>/dev/null" );

    const std::vector<crossref::RefInfo> refs = crossref::enumerateRefs( root, filter, result.headSha );
    if( refs.size() > crossref::kMaxRefs ) { result.ok = false; result.tooManyRefs = true; return result; }
    result.refsScanned = refs.size();

    const layout::AggIndex byName = layout::buildAggIndex( ing );
    layout::ModelCtx        ctx( ing, byName );
    const PathIndex         byPath = buildCandidates( ctx, root );
    for( const auto& [ path, cands ] : byPath ) { (void)path; result.candidates += cands.size(); }

    HeadCache           headCache;
    std::vector<RefRow> rows( refs.size() );
    for( std::size_t i = 0; i < refs.size(); ++i ) rows[i].ref = refs[i];

    SweepState sw;
    collectAuthoredSites( root, refs, byPath, sw, Tally{ rows, result } );   // WHERE each ref's own work reaches
    modelRefBlobs( root, ctx, byPath, sw, result );                          // one cat-file batch for both sides

    const ClassifyCtx cc{ ctx, headCache, result };
    for( const PathSite& ps : sw.pathSites )                                 // the verdict per candidate
        classifyPathSite( cc, byPath, sw, ps, rows[ ps.refIndex ] );

    // ── rank: the biggest contract break leads ───────────────────────────────────────────────────────────
    // Breaks before reports, then by SIZE DELTA descending (a struct that grew 200 bytes outranks one that
    // grew 4), then by HEAD's own size (a vanished 4 KB table outranks a vanished 8-byte pair), then a
    // total order on (path, name) so the output is byte-identical run to run.
    for( RefRow& r : rows )
    {
        std::sort( r.structs.begin(), r.structs.end(), []( const StructRow& a, const StructRow& b )
        {
            const bool ab = kindIsBreak( a.kind ), bb = kindIsBreak( b.kind );
            if( ab != bb )                     return ab;
            const bool al = kindListed( a.kind ), bl = kindListed( b.kind );
            if( al != bl )                     return al;
            if( a.sizeDelta != b.sizeDelta )   return a.sizeDelta > b.sizeDelta;
            if( a.headSize  != b.headSize )    return a.headSize  > b.headSize;
            if( a.path != b.path )             return a.path < b.path;
            return a.name < b.name;
        } );
        // A ref with NO rows at all is genuinely quiet and folds into quiet=. A ref whose every row is an
        // excluded kind is kept here (so --detail can print it) and skipped by the DEFAULT body, which
        // counts it in excluded_refs= — the two reasons a ref is invisible must not share one number.
        if( r.counts.total() == 0 ) { ++result.quietRefs; continue; }
        result.refs.push_back( std::move( r ) );
    }
    std::sort( result.refs.begin(), result.refs.end(), []( const RefRow& a, const RefRow& b )
    {
        const std::uint32_t ad = a.counts.breaks(), bd = b.counts.breaks();
        if( ad != bd ) return ad > bd;
        return a.ref.name < b.ref.name;
    } );
    return result;
}

// ── XML emission (G4: minified, xmllint-clean; no `\n` outside CDATA, no double hyphen in a comment) ──────

using XmlEscaper = std::function<std::string( std::string_view )>;

inline void writeAbiCaveats( std::FILE* out, const char* tag, const std::vector<layout::Caveat>& cs, const XmlEscaper& ex )
{
    for( const layout::Caveat& c : cs )
        std::fprintf( out, "<%s k=\"%s\" d=\"%s\"/>", tag, ex( c.kind ).c_str(), ex( c.detail ).c_str() );
}

inline void writeAbiStruct( std::FILE* out, const StructRow& s, const XmlEscaper& ex )
{
    // ref_size/size_differs are meaningful only when the ref side was actually SIZED: "absent" has no bytes
    // at all, and "unknown" refused to place a number (finalizeLayout leaves size at 0, which would print
    // as ref_size="0" and read as "an empty struct" — a plausible-looking wrong number of exactly the kind
    // the honesty contract exists to prevent). Omitted rather than printed as a misleading 0.
    std::fprintf( out, "<struct n=\"%s\" p=\"%s\" l=\"%u\" kind=\"%s\" head_size=\"%u\"",
                  ex( s.name ).c_str(), ex( s.path ).c_str(), s.headLine, s.kind, s.headSize );
    if( s.refSized ) std::fprintf( out, " ref_size=\"%u\" size_differs=\"%d\" size_delta=\"%u\"",
                                   s.refSize, s.sizeDiffers ? 1 : 0, s.sizeDelta );
    std::fprintf( out, ">" );
    for( const layout::FieldDiff& f : s.fields )
        std::fprintf( out, "<d n=\"%s\" a=\"%s\" b=\"%s\"/>", ex( f.name ).c_str(), ex( f.inA ).c_str(), ex( f.inB ).c_str() );
    writeAbiCaveats( out, "head_caveat", s.headCaveats, ex );
    writeAbiCaveats( out, "ref_caveat",  s.refCaveats,  ex );
    std::fprintf( out, "</struct>" );
}

// Every kind with a non-zero tally, as attributes, in kKindPolicy order (a fixed order = a deterministic
// attribute sequence). Zero-valued kinds are omitted so a clean sweep reads clean.
inline void writeKindAttrs( std::FILE* out, const KindCounts& k )
{
    for( std::size_t i = 0; i < kKindCount; ++i )
        if( k.n[i] ) std::fprintf( out, " %s=\"%u\"", kKindPolicy[i].tag, k.n[i] );
}

// How many of a ref's rows THIS view would print, before the per-ref display cap. One definition, read by
// the header pre-pass, the ref attributes and the body filter alike — they must never disagree.
inline std::size_t eligibleRows( const RefRow& r, bool listAll ) noexcept
{
    std::size_t n = 0;
    for( const StructRow& s : r.structs ) if( listAll || kindListed( s.kind ) ) ++n;
    return n;
}

inline void writeAbiRef( std::FILE* out, const RefRow& r, const XmlEscaper& ex, std::size_t maxStructs, bool listAll )
{
    const std::size_t eligible   = eligibleRows( r, listAll );
    const std::size_t shownCount = std::min( eligible, maxStructs );

    // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY, rule 3): shown= shipped here without
    // its capped= companion, so a <ref> at exactly maxStructs rows read as complete. The bit is against
    // `eligible` — the rows THIS VIEW lists — not against rows=, which counts every parsed struct including
    // the kinds this view excludes; <more structs="N"/> below already states the same fact as a count.
    std::fprintf( out, "<ref name=\"%s\" tip=\"%.9s\" date=\"%s\" rows=\"%zu\" shown=\"%zu\" capped=\"%u\" excluded=\"%u\" head_only=\"%u\"",
                  ex( r.ref.name ).c_str(), r.ref.tip.c_str(), ex( r.ref.date ).c_str(),
                  r.structs.size(), shownCount, unsigned( shownCount < eligible ), r.counts.excluded(), r.headOnly );
    writeKindAttrs( out, r.counts );
    std::fprintf( out, ">" );

    std::size_t shown = 0;
    for( const StructRow& s : r.structs )
    {
        if( !listAll && !kindListed( s.kind ) ) continue;
        if( shown++ >= maxStructs ) break;
        writeAbiStruct( out, s, ex );
    }
    if( eligible > shownCount ) std::fprintf( out, "<more structs=\"%zu\"/>", eligible - shownCount );
    std::fprintf( out, "</ref>" );
}

inline void writeAbiCheck( std::FILE* out, const AbiResult& res, std::size_t maxStructs, bool listAll )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY, rule 3): `droppedRows` is a COUNT and
    // used to be printed as capped= — the one place in the tool where that attribute held a number instead
    // of the boolean every other verb spells there, so `capped="12"` and `capped="1"` meant unrelated
    // things under one name. The count keeps its meaning under the honest name dropped=; capped= is the
    // boolean, and rows= still reconciles exactly as shown + dropped + excluded.
    std::uint32_t brokenRefs = 0, shownRows = 0, droppedRows = 0, excludedRefs = 0;
    for( const RefRow& r : res.refs )
    {
        if( r.counts.breaks() > 0 ) ++brokenRefs;
        const std::uint32_t eligible = std::uint32_t( eligibleRows( r, listAll ) );
        if( eligible == 0 ) { ++excludedRefs; continue; }
        const std::uint32_t shown = std::uint32_t( std::min<std::size_t>( eligible, maxStructs ) );
        shownRows   += shown;
        droppedRows += eligible - shown;
    }

    // G4: an XML comment may not contain a double hyphen, so this text names flags and git subcommands
    // WITHOUT their leading dashes (the same rule layout.h's and crossref.h's own comments follow).
    std::fprintf( out, "<!-- ripwire abi: the cross-branch ABI-BREAK gate — layout(STRUCT) crossed with "
                       "stray-content(BRANCH). Scope is what each ref AUTHORED: the paths `diff base..tip` "
                       "reports against its own merge base, never `diff HEAD..tip` (a file the branch never "
                       "opened cannot be a break the branch introduced, and on a long-lived tree that one "
                       "distinction took 487 drift rows to 4). For each such path the SAME field-offset model "
                       "layout uses is run LEXICALLY on the ref's git blob (never indexed) and compared "
                       "against HEAD's computed fields. LISTED kinds: drift = the byte contract differs (the "
                       "bug this check exists for, the only kind that exits 2); unknown = the ref-side copy "
                       "could not be modelled (see ref_caveat) and is NEVER reported as unchanged; absent = "
                       "the ref does not define the struct at that path. COUNTED but not listed (pass "
                       "detail=N to print them): rename = identical slots and field types under different "
                       "field NAMES, so every byte stayed where it was (a same-type field REORDER is "
                       "lexically identical to a rename and lands here too); spelling and stub mirror "
                       "layout's own harmless cases; head-moved = the ref's copy equals its own merge-base "
                       "copy, so the LIVE LINE is what changed. head_only= counts candidate sites on paths "
                       "only the live line touched (outside the authored scope); unmodelable= counts sites "
                       "skipped because HEAD's own copy carries no baseline; every excluded row is on a "
                       "counter, nothing is dropped silently. Structs that match are omitted entirely; a ref "
                       "with no rows at all is counted in quiet=, and a ref whose every row is an excluded "
                       "kind is counted in excluded_refs= and prints under detail=N. LIMITS: HEAD's own side is the "
                       "WORKING TREE's layout answer, not a re-fetched git blob at HEAD's commit; a nested "
                       "field type that ALSO changed on the ref resolves via HEAD's copy, not the ref's; the "
                       "ref-side locator is index-free and file-scope (one namespace deep) only, so a struct "
                       "nested in a class or wrapped in an extern C block reads absent rather than compared; "
                       "the authorship anchor is per PATH, so a branch changing struct S in one file while "
                       "the live line changes S's mirror in another is a merge hazard only layout(S) on the "
                       "merged result can see. Single-root; read-only (cat-file/diff/merge-base only). -->" );
    std::fprintf( out, "<abi head=\"%.9s\" head_ref=\"%s\" refs=\"%zu\" candidates=\"%zu\" compared=\"%zu\" blobs=\"%zu\""
                       " rows=\"%u\" shown=\"%u\" capped=\"%u\" dropped=\"%u\" excluded=\"%u\" head_only=\"%zu\" unmodelable=\"%zu\""
                       " unrelated=\"%u\" broken_refs=\"%u\" quiet=\"%u\" excluded_refs=\"%u\"",
                  res.headSha.c_str(), ex( res.headRef ).c_str(), res.refsScanned, res.candidates, res.compared,
                  res.distinctBlobs, res.counts.total(), shownRows, unsigned( droppedRows > 0 ), droppedRows, res.counts.excluded(),
                  res.headOnly, res.unmodelable, res.unrelated, brokenRefs, res.quietRefs, excludedRefs );
    writeKindAttrs( out, res.counts );
    std::fprintf( out, ">" );
    for( const RefRow& r : res.refs )
        if( eligibleRows( r, listAll ) > 0 )           // rows but none this view lists -> counted in excluded_refs=
            writeAbiRef( out, r, ex, maxStructs, listAll );
    std::fprintf( out, "</abi>" );
}

}}   // namespace ctx::abicheck
