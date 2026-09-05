#pragma once

// mcpverbs.h — the per-verb text/JSON builders for --mcp: the pure functions each MCP
// read/flagship verb dispatches to (analyzeToString / for / lego / owners / exemplar / impact /
// uses / path_between / connect / quality_delta / fetch_body / batch, …). Each reuses the warm
// McpIndex via getIndex() and returns the verb's answer body verbatim. Extracted from mcp.h (the
// mcp.h/main.cpp concern-split). Includes mcpindex.h; included by mcp.h (runMcp dispatches here).

#include "mcpindex.h"
#include "gitmine.h"       // B3: gitRecentCommitFileSets + applyCoChangeBoost — the `for` verb's co-change prior (same boost as CLI --for)
#include "ownersview.h"    // §P6.4: countUniformOwnership/ownershipRowsToPrint — shared with main.cpp's --owners CLI path
#include "gitstamp.h"      // §P8: gitstamp::atAttr/stampAt — the at="<sha>[+dirty]" anchor on the git-history verbs
#include "mention.h"       // B8: applyMentionBoost — the `for` verb's query-mention anchor (same default-on behavior as CLI --for)
#include "filter.h"        // §P4: rankTierSymbolMultipliers — the fixture/present tier down-weight the CLI ranking lenses apply
#include "redact.h"        // RedactCounts — the per-request redaction tally threaded through the body/doc verbs
#include "packtask.h"      // L4: the shared --pack-task / MCP explore+pack_task bundle assembler (packTaskBundleText)
#include "partition.h"     // the explore verb's `partition` argument (packTaskPartitionText)
#include "tracelocus.h"    // L4: the shared --from-trace / MCP from_trace bundle assembler (fromTraceBundleText)
#include "editcheck.h"     // L4: the shared --edit-check / MCP edit_check contract-comparison core (editCheckBundleText)
#include "graphlegend.h"   // §H4 §3.4: the ONE counts_floor= marker + shared graph-count legend wording (CLI ≡ MCP)
#include "crossref.h"      // the shared cross-branch content index (whereis / stray_content)
#include "darkflags.h"     // the shared dark-content gate harvest (flags)
#include "flipimpact.h"    // the flags verb's `symbol` argument: one gate's flip blast radius
#include "docdrift.h"      // the shared doc-anchor verifier (doc_drift)
#include "exemplar.h"      // §B6 M2: selectExemplar + kExemplarSelectionRule — the ONE selector/wording both surfaces use
#include "mcprefusal.h"    // §B6 M7/M8/M9: the shared verb+field refusal table both MCP arms speak
#include "sarif.h"         // G1 (2026-08-15): rw::sarif::rootRelativeUri/rootPrefixOf — grepHitsJson's root-relative `file` (CLI ≡ MCP, no re-derivation)
#include "slice.h"         // lane/tc-sliceat: the shared --slice / MCP slice def-use core (sliceBundleText — ONE emitter, two surfaces)
#include "fielduses.h"     // the member-variable round: the ONE --uses=Owner.field renderer (renderFieldUses — CLI ≡ MCP)

#include <filesystem>      // §B6 M3: the shared root-path existence/directory check (mcpRootRefusal below)
#include <span>            // std::span — connectemit::rebuildFromLegs reads the caller's retained-leg mask

namespace rw
{

// ─── §B6 M4: the ONE place both MCP arms read a paging window ────────────────────────────────────────────
//
// The `impact` and `whereis` legends both instructed "raise the default cap with limit=N (offset=M pages)"
// — and no MCP tool declared either field, so passing them was silently ignored and the two answers were
// byte-identical with and without them. §P15.3 killed that accept-and-ignore class on the CLI arm only.
//
// The knobs are now real rather than the sentence removed, because the underlying verbs already page
// correctly (pageview.h's pageWindow/effectiveRowCap/pageDisclosure, and crossref's writeWhereisPage): the
// CLI has had the window for these two verbs since §P8 and the MCP surface was simply not passing it.
//
// This reader exists so the two dispatch arms cannot drift: the live server's tools/call scope and the
// batch verb's sub-query object are both flat JSON spans, so ONE extractor serves both and "does the batch
// arm honor limit?" has one answer.
//
// ─── verifier N2/N3: PRESENT-BUT-INVALID is a refusal, not a default ─────────────────────────────────────
//
// M4 made limit/offset REAL; it did not make them HONEST. The original clampPos mapped every non-positive,
// non-numeric and fractional value onto 0 = "absent", so `limit:0`, `limit:-1`, `limit:"abc"` and
// `offset:-2` were accepted and silently ignored and `limit:3.9` was truncated to 3 — while the CLI twin
// refuses all five loudly. `connect`'s radius was a notch worse: a bare `std::uint32_t(radArg)` cast, so
// `radius:2^40` WRAPPED to 0 and clamped to radius="1" — a different question, answered with confidence,
// under a number the caller never typed.
//
// mcpIntArg closes the whole class at ONE seam for both arms and every verb: ABSENT still means the verb's
// own default (the un-paged answer stays byte-identical), and present-but-outside-the-domain returns the
// mcprefusal.h sentence carrying the domain, the value as typed, and a runnable example.
struct McpIntArg
{
    long long   value     = 0;    // meaningful only when isPresent && refusal.empty()
    bool        isPresent = false;
    std::string refusal;          // non-empty ⇒ the caller must refuse this request
};

inline McpIntArg mcpIntArg( const std::string& scope, const char* field, long long least, long long most )
{
    const mcpdetail::RawValue raw = mcpdetail::findRawValue( scope, field );
    if( !raw.isPresent )
    {
        return {}; // absent ⇒ the verb's default, untouched
    }

    long long v = 0;
    // a QUOTED integer still parses (findInt has always accepted "3", and a client that stringifies its
    // numbers is not asking a different question); a quoted NON-integer falls through to the refusal.
    if( !mcpdetail::parseWholeInt( raw.text, v ) || v < least || v > most )
    {
        return { 0, true, mcprefuse::badValueRefusal( field, raw.text ) };
    }
    return { v, true, {} };
}

// The STRING-typed twin (verifier N11). A field the inputSchema declares as a string, given as an ARRAY,
// read as absent through findString — and `situational_awareness` then answered about `git diff` and
// reported a clean working tree with total confidence. Absent still means the verb's default.
//
// W3FIX H5: N11 wired this into `files` and stopped there, so thirteen more schema-typed string fields kept
// the bare findString path and kept silently ignoring a wrong-shaped value — including
// `situational_awareness diff:["a","b"]`, which is the SAME confidently-wrong clean-tree answer one field
// over, and `kind`/`symbol` across whereis / stray_content / flags / doc_drift / owners. Both arms now read
// every string argument through here, so the shape check is a property of the reader, not of remembering.
//
// The decode reads the occurrence the SHAPE check accepted (raw.valuePos), not a second independent lookup —
// with duplicate keys pinned first-wins (mcpjson.h) those are the same bytes, and saying so in code is what
// keeps them the same bytes.
struct McpStringArg { std::string value; std::string refusal; };

inline McpStringArg mcpStringArg( const std::string& scope, const char* field )
{
    const mcpdetail::RawValue raw = mcpdetail::findRawValue( scope, field );
    if( !raw.isPresent )
    {
        return {};
    }
    if( !raw.isQuoted )
    {
        return { {}, mcprefuse::badValueRefusal( field, raw.text ) };
    }
    return { mcpdetail::decodeStringAt( scope, raw.valuePos ), {} };
}

// The BOOLEAN-typed twin (P9, capture-audit 2026-09-04). `post_check` is the first schema-typed boolean
// argument in this server, and it gets a reader for exactly the reason the string and int twins have one:
// absent must mean the verb's default, a present-but-wrong-shaped value must REFUSE naming the field, and
// neither may collapse into the other. The two JSON literals are the whole vocabulary — a quoted "false" is
// a string, not a boolean, and is refused rather than guessed at (the badValueRefusal wording every other
// typed reader uses).
struct McpBoolArg { bool value = false; bool isPresent = false; std::string refusal; };

inline McpBoolArg mcpBoolArg( const std::string& scope, const char* field )
{
    const mcpdetail::RawValue raw = mcpdetail::findRawValue( scope, field );
    if( !raw.isPresent )
    {
        return {};
    }
    if( raw.isQuoted || ( raw.text != "true" && raw.text != "false" ) )
    {
        return { false, true, mcprefuse::badValueRefusal( field, raw.text ) };
    }
    return { raw.text == "true", true, {} };
}

// The ARRAY-typed twin (W3FIX M8). `symbols` / `queries` / `paths` are the three schema-typed arrays, and a
// present-but-wrong-shaped value (`connect symbols:5`, `batch queries:5`, `analyze paths:5`) read as absent
// through findArray — so both arms answered "missing required field: X" for a field the caller DID send,
// which is exactly the absent-vs-wrong-shape collapse findRawValue exists to separate. The element-COUNT
// domain lives here too, so `connect symbols:["main"]` gets the table's domain clause and a runnable example
// instead of the bespoke "connect needs 2..16 symbols (got 1)" fourth dialect.
//
// `acceptsCsv` is a COLUMN, not a guess: `connect symbols` documents a lenient comma-string form, the other
// two do not, and a reader that silently accepted a string for `queries` would be inventing a shape.
struct McpArrayArg
{
    std::string              span;              // the '[…]' span (or the comma-string) exactly as typed; "" when absent
    std::vector<std::string> strings;           // its "…" elements in order, or the split comma-string
    bool                     isPresent = false;
    std::string              refusal;           // non-empty ⇒ the caller must refuse this request
};

inline McpArrayArg mcpArrayArg( const std::string& scope, const char* field, bool acceptsCsv,
                                std::size_t leastCount = 0, std::size_t mostCount = ~std::size_t( 0 ) )
{
    const mcpdetail::RawValue raw = mcpdetail::findRawValue( scope, field );
    if( !raw.isPresent )
    {
        return {};
    }

    McpArrayArg out;
    out.span      = raw.text;
    out.isPresent = true;

    if( raw.isArray )
    {
        out.strings = mcpdetail::arrayStrings( scope, field );
    }
    else if( acceptsCsv && raw.isQuoted )
    {
        // the documented lenient form: "a,b,c" → {a,b,c}. Empty fragments are dropped, not passed on as
        // unresolvable symbol names, exactly as the pre-M8 hand-rolled split at the connect dispatch did.
        const std::string csv = mcpdetail::decodeStringAt( scope, raw.valuePos );
        for( std::size_t start = 0; start <= csv.size(); )
        {
            const std::size_t comma = csv.find( ',', start );
            const std::string tok   = csv.substr( start, comma == std::string::npos ? std::string::npos : comma - start );
            if( !tok.empty() )
            {
                out.strings.push_back( tok );
            }
            if( comma == std::string::npos )
            {
                break;
            }
            start = comma + 1;
        }
    }
    else
    {
        return { raw.text, {}, true, mcprefuse::badValueRefusal( field, raw.text ) };
    }

    if( out.strings.size() < leastCount || out.strings.size() > mostCount )
    {
        out.refusal = mcprefuse::badValueRefusal( field, raw.text );
    }
    return out;
}

// The OBJECT-typed twin (§B6 M7), for the two envelope objects: `params` and `params.arguments`. findObject
// returns "" for BOTH "absent" and "present but not an object", and that collapse was the quietest bug on the
// surface: `arguments:5` — and the common host bug of sending `arguments` as a STRING of JSON — fell back to
// the `params` scope, so the caller's `path` VANISHED and the verb answered about the default startup root
// with total confidence (measured: files=6 for a request that named a 1-file subdir). Same class as the
// wrong-shaped `paths` W3FIX M8 fixed one level down; this is that fix at the envelope.
//
// `null` reads as ABSENT, deliberately: JSON-RPC 2.0 forbids it, MCP hosts send it anyway for "no parameters"
// (test/mcpreadloopcheck.sh's hostile corpus carries both `params:null` and `arguments:null`), and null
// genuinely carries no arguments — which is what absent means. Refusing it would break handshakes for no
// honesty gain. An ARRAY is refused rather than tolerated: positional params are legal JSON-RPC but this
// server reads arguments BY NAME, so an array's contents could never be read and silence would drop them.
struct McpObjectArg
{
    std::string span;                  // the '{…}' span exactly as typed; "" when absent
    bool        isPresent = false;
    std::string refusal;               // non-empty ⇒ the caller must refuse this request
};

inline McpObjectArg mcpObjectArg( const std::string& scope, const char* field )
{
    const mcpdetail::RawValue raw = mcpdetail::findRawValue( scope, field );
    if( !raw.isPresent )
    {
        return {};
    }
    if( !raw.isQuoted && !raw.isArray && raw.text == "null" )
    {
        return {}; // "no parameters" — absent
    }
    if( raw.isQuoted || raw.isArray || raw.text.empty() || raw.text.front() != '{' )
    {
        return { {}, false, mcprefuse::badValueRefusal( field, raw.text ) };
    }
    return { mcpdetail::containerSpanAt( scope, raw.valuePos, '{', '}' ), true, {} };
}

// ─── §B6 M3: does `path` name a readable DIRECTORY? ONE check, for every index-backed verb ────────────────
//
// The false-zero class (see mcprefusal.h's rootRefusal for the finding): a nonexistent path and a file-as-path
// both produced all-zero SUCCESS reports. The check is ONE call in dispatchMcpLine, placed after the `paths`
// rebind and the workspace/default-root policy gates and BEFORE the dispatch chain, because the sibling sweep
// showed the damage is not limited to the six verbs that answer zeros: the other verbs "refuse", but with a
// FALSE CAUSE ("symbol not found: 'distance'" when there is no tree to look in, "not a git repository" for a
// path that does not exist at all). One shared check makes all 30 name the real condition, and none of them
// reaches getIndex() first.
//
// A registered multi-root workspace KEY is not a filesystem path (it is the \x1f-joined realpath join), so the
// key's own ROOTS are checked instead — the check must never stat a key, and the refusal must never render one.
inline std::string mcpRootDirRefusal( const std::string& dir )
{
    std::error_code                     ec;
    const std::filesystem::file_status  st = std::filesystem::status( std::filesystem::path( dir ), ec );
    if( ec || !std::filesystem::exists( st ) )
    {
        return mcprefuse::rootRefusal( mcprefuse::RootFault::Missing, dir );
    }
    if( !std::filesystem::is_directory( st ) )
    {
        return mcprefuse::rootRefusal( mcprefuse::RootFault::NotADirectory, dir );
    }
    return {};
}

// is `path` a REGISTERED multi-root workspace key (2+ roots), rather than a plain directory path? The one
// predicate both the root check above and the single-root verb refusals (§B6 M9) ask.
inline bool isMcpMultiRootPath( const std::string& path )
{
    const auto it = mcpWorkspaceRegistry().find( path );
    return it != mcpWorkspaceRegistry().end() && it->second.size() >= 2;
}

inline std::string mcpRootRefusal( const std::string& path )
{
    const auto it = mcpWorkspaceRegistry().find( path );
    if( it != mcpWorkspaceRegistry().end() && it->second.size() >= 2 )
    {
        for( const WorkspaceRoot& r : it->second )
        {
            if( const std::string rootErr = mcpRootDirRefusal( r.arg ); !rootErr.empty() )
            {
                return rootErr;
            }
        }
        return {};
    }
    return mcpRootDirRefusal( path );
}

// The paging pair, read through mcpIntArg so both fields speak the one refusal. `kMcpPageValueMax` restates
// cli.h's kPageValueMax (parsePosInt's own ceiling) so the MCP arm accepts exactly the CLI's range — the two
// headers cannot include each other, so the number is restated with its source named rather than guessed.
struct McpPageArgs  { int limit = 0; int offset = 0; };
struct McpPageParse { McpPageArgs page; std::string refusal; };

inline constexpr long long kMcpPageValueMax = 1000000000;   // == cli.h's kPageValueMax

// W3FIX M5: memory_recall's `top_k` ceiling, formerly an UNDECLARED silent clamp — `top_k:2^40` came back as
// 1000 documents with nothing saying so, which is the accept-and-ignore class wearing a plausible number.
// It is a declared DOMAIN now: the tools/list stanza states 1..1000, mcprefusal.h's row states it, and a
// value outside the band is refused rather than quietly rewritten (the §B8.1 ruling, same as radius).
inline constexpr long long kMcpRecallTopKMax = 1000;

inline McpPageParse mcpPageArgs( const std::string& scope )
{
    const McpIntArg limitArg = mcpIntArg( scope, "limit", 1, kMcpPageValueMax );
    if( !limitArg.refusal.empty() )
    {
        return { {}, limitArg.refusal };
    }

    const McpIntArg offsetArg = mcpIntArg( scope, "offset", 0, kMcpPageValueMax );
    if( !offsetArg.refusal.empty() )
    {
        return { {}, offsetArg.refusal };
    }

    return { { int( limitArg.value ), int( offsetArg.value ) }, {} };   // absent ⇒ 0 ⇒ the un-paged window
}

// ─── W3FIX M4: the unknown-ARGUMENT refusal, for both arms ───────────────────────────────────────────────
//
// The near-miss class in one sentence: `explore` honors `budget_tokens`, and `token_budget` / `max_tokens`
// were read by nothing and silently dropped — the bundle came back at the default with nothing saying the
// budget had been ignored. Rather than adding the two aliases and waiting for the fourth name, an argument
// the verb's inputSchema does not declare is REFUSED, with a near-miss against that verb's own field set
// (which is what makes `token_budget` → `budget_tokens` land) and the set listed for recovery.
//
// One helper, both arms: the live server passes its `arguments` scope and the tool name; the batch arm passes
// one sub-query object and the batch item schema. `declared` is a PARAMETER rather than a lookup inside,
// because those really are two different schemas — pretending otherwise is how a shared helper starts lying
// about one of its callers.
inline std::string mcpUnknownFieldRefusal( const std::string& scope, std::string_view verb,
                                           std::span<const std::string_view> declared )
{
    if( declared.empty() )
    {
        return {}; // an unadvertised name — the unknown-TOOL refusal owns that request
    }

    for( const std::string& field : mcpdetail::objectKeys( scope ) )
    {
        if( !mcprefuse::isFieldAccepted( declared, field ) )
        {
            return mcprefuse::unknownFieldRefusal( verb, field, declared );
        }
    }
    return {};
}

// Capture one FILE*-writing renderer into a string. The three verbs below differ only in which writer they
// run, so the open_memstream boilerplate lives here once instead of three times.
inline std::string captureXml( const std::function<void( std::FILE* )>& render )
{
    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {}; // alloc failure → empty, never deref NULL
    }
    render( mem );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// full pipeline on a dir → XML captured into a string (captureXml, above).
//
// §B6 M1 — the two COMPLETENESS gauges are passed, not nulled. This front door handed serialize() null
// ambOut/unresolvedOut, and serialize prints a null accumulator as a hard `ambiguous=0 unresolved=0`
// (unlike `precise=`, which it OMITS when null) — so the agent surface claimed a perfectly resolved call
// graph where the CLI's same map reports thousands of guessed calls, and the 35 per-row `amb=` markers the
// legend advertises never appeared. The counters already live on the warm index's graph (g.ambOut /
// g.unresolvedOut, filled by buildGraph's resolve loop); nothing is computed here that was not computed
// before, it is only no longer discarded on the way to the emitter.
//
// §B6 M10 — statsFirstScreen: the MCP server runs `stable` by default (main.cpp's --mcp turns it on), which
// moves the files=/symbols=/shown=/order= stanza to a TRAILING comment. That is a CLI KV-cache optimization;
// on this surface it left the first screen with no denominator and no order marker. One argument, one
// placement change, same single emission.
//
// The same call also passes outProv and bindLabel, on the SAME reasoning and with the same emptiness
// convention main.cpp uses (`empty() ? nullptr : &`). `precise=` is NOT a SCIP-only attribute — outProv
// also carries FFI binding provenance, which this tree has (precise="3") with no --scip anywhere, so
// withholding it dropped a real edge-provenance fact and a real bind= identity from the agent's map.
// (Found by test/mcpclidiffcheck.sh, which is the point of having it: the first version of this fix
// null-passed both and explained the absence away.)
inline std::string analyzeToString( const std::string& root, int topK, bool stable = false )
{
    const McpIndex& ix = getIndex( root );                  // parse once, reuse across calls
    // ── verifier FINDING E3 (2026-08-19): this verb is the default map's own MCP twin and serialize() has
    //    taken a rootArg since the root-relative round — this call site simply never passed it, so the same
    //    corpus answered the CLI question with `src/main.cpp` and the MCP twin of that question with the
    //    absolute path (85 rows on ripwire's own tree). Same single-root condition every other MCP verb
    //    uses; serialize() emits root= and the shared legend clause from there, so nothing else moves.
    const std::string_view anRootArg = ix.ing.realPaths.empty() ? std::string_view( root ) : std::string_view();
    return captureXml( [ & ]( std::FILE* f )
                       { serialize( f, ix.ing, ix.rank, ix.g.outOff, ix.g.outTargets, topK,
                                    /*mostImportantLast=*/false, /*metrics=*/false, /*fanIn=*/nullptr,
                                    &ix.g.ambOut, stable,
                                    ix.g.outProv.empty() ? nullptr : &ix.g.outProv,
                                    /*cbo=*/nullptr, /*tested=*/nullptr,
                                    /*lcom4=*/nullptr, /*amp=*/nullptr, &ix.g.unresolvedOut,
                                    ix.g.bindLabel.empty() ? nullptr : &ix.g.bindLabel,
                                    /*autoOrder=*/false, /*outEstTokens=*/nullptr,
                                    /*extraBodyTokens=*/0,
                                    // W2-F: the map's convergence disclosure. The CLI map carries pr_iters= and
                                    // this one must too — "the clause landed at 3 of its 5 echo sites" is the
                                    // §B4 family, and mcpclidiffcheck is the gate that keeps the two surfaces one.
                                    /*ann=*/rw::MapAnnotations{ .prDisclosure = ix.prDisclosure },
                                    /*statsFirstScreen=*/true, anRootArg, &ix.g.locPinOut, ix.g.externalCalls ); } );
}

// ─── the cross-branch + dark-content MCP twins (`whereis`, `stray_content`, `flags`) ───
// Each is a thin front door onto the SAME computation + the SAME renderer its CLI sibling calls
// (crossref.h / darkflags.h), captured with the open_memstream idiom above — one XML shape, two surfaces,
// no forked logic. Unlike `merge_scout` (CLI-only: it takes a hand-authored ref LIST), these three take no
// multi-ref UX — a symbol, an optional substring filter, nothing else — so they carry over cleanly.
//
// `stray_content` and `whereis` read OTHER refs' blobs, which the MCP index never ingested; they use `root`
// only, and deliberately do NOT touch getIndex() (no rebuild, no staleness coupling). `flags` DOES need the
// crawled file list, so it goes through getIndex() like every other index-backed verb.

// `whereis` verb: which ref's tree defines or mentions SYM. "" ⇒ not a git repo (the caller reports it).
//
// §A7: this surface passes NO WhereisEvidence, so its HEAD rows keep the lexical shape heuristic and the root
// says so (head_labels="lexical"). That is deliberate and is the paragraph above's rule, not an oversight:
// supplying the index's def sites means calling getIndex(), which would couple this verb to index staleness
// for the sake of a LABEL. The CLI, which has already built an index for the run, supplies them.
//
// §B6 M4: `page` is the request's limit/offset (mcpPageArgs, above). writeWhereisPage is the SAME entry
// point the CLI --whereis calls with cfg.pageLimit/cfg.pageOffset, so the legend's "raise the default cap
// with limit=N (offset=M pages)" is now true on this surface too, with the same has_more=/next_offset=
// disclosure that lets a paging loop terminate. Defaulted to {} ⇒ byte-identical to the un-paged answer.
inline std::string whereisText( const std::string& root, const std::string& symbol, const std::string& filter,
                                std::size_t maxHits, McpPageArgs page = {} )
{
    const crossref::WhereResult res = crossref::computeWhereis( root, symbol, filter );
    if( !res.ok )
    {
        return {};
    }
    return captureXml( [ & ]( std::FILE* f ) { crossref::writeWhereisPage( f, res, maxHits, page.limit, page.offset ); } );
}

// `stray_content` verb: per ref, the content its own divergent work authored that the live line lacks.
inline std::string strayContentText( const std::string& root, const std::string& filter, std::size_t maxFiles )
{
    const crossref::StrayResult res = crossref::computeStrayContent( root, filter );
    if( !res.ok )
    {
        return {};
    }
    return captureXml( [ & ]( std::FILE* f ) { crossref::writeStrayContent( f, res, maxFiles ); } );
}

// `flags` verb: the dark-content dashboard. Index-backed (it needs the crawled file list).
inline std::string flagsText( const std::string& root, const std::string& filter, std::size_t maxSites )
{
    const McpIndex& ix = getIndex( root );
    const darkflags::FlagsResult res = darkflags::computeFlags( ix.ing, root, {}, filter );
    return captureXml( [ & ]( std::FILE* f ) { darkflags::writeFlags( f, res, maxSites ); } );
}

// `flags` verb with the optional `symbol` argument = the CLI's `--flags --flip=NAME`: the blast radius of
// turning ONE gate on. An ARGUMENT rather than a 31st verb, because it is the same question at a different
// zoom (list every gate / size this one) and the caller already has the gate name from the list. Also
// index-backed, and unlike the plain lane it needs the call graph too (ix.g). "" ⇒ no such gate: the
// handler turns that into a -32602 naming the near-misses, never an empty-looking success.
inline std::string flipText( const std::string& root, const std::string& gate, std::size_t maxRows,
                             std::vector<std::string>& nearMissesOut )
{
    const McpIndex&                  ix  = getIndex( root );
    const flipimpact::FlipResult     res = flipimpact::computeFlip( ix.ing, ix.g, root, {}, gate );
    if( !res.ok ) { nearMissesOut = res.nearMisses; return {}; }
    return captureXml( [ & ]( std::FILE* f ) { flipimpact::writeFlip( f, res, ix.ing, root, maxRows ); } );
}

// `doc_drift` verb: the markdown docs' checkable anchors vs the live index. Index-backed —
// it needs both the crawled file list AND the symbol table, so it goes through getIndex() like `flags`.
inline std::string docDriftText( const std::string& root, const std::string& filter, std::size_t maxPerDoc )
{
    const McpIndex& ix = getIndex( root );
    const docdrift::DriftResult res = docdrift::computeDocDrift( ix.ing, root, {}, filter );
    return captureXml( [ & ]( std::FILE* f ) { docdrift::writeDocDrift( f, res, maxPerDoc ); } );
}

// build ing+graph for `root`, resolve `name`, return a JSON object: the symbol + its callers
// (in-edges) and — unless referencingOnly — its callees (out-edges). "" if the symbol isn't found.
// (find_symbol / find_referencing_symbols — the Serena/LocAgent agent verbs, answered from the CSR.)
inline std::string symbolQueryJson( const std::string& root, const std::string& name, bool referencingOnly )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;
    const NodeId        f   = resolveFocus( ing, name );
    if( f == kNoNode || f >= ing.symbols.size() )
    {
        return {};
    }

    // R-E fix (2026-08-19): root-relative "file" values + a "root" key. This verb has no CLI twin to diverge
    // from, but an agent that reads `file` here and `p=` from callers/callees in the same task must not be
    // handed two path dialects for one tree — that is the whole point of the root-relative round.
    const bool         sqSingleRoot = ing.realPaths.empty();
    const std::string  sqRootPrefix = sqSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const auto symObj = [ & ]( NodeId id ) -> std::string
    {
        const Symbol& s = ing.symbols[id];
        // T4: attach the stable content-handle so the agent can `fetch_body{handle}` instead of us re-sending
        // the body. Names/signatures by default (this verb); bodies by handle on request.
        return std::string( "{\"name\":\"" ) + mcpdetail::jsonEscape( s.name )
             + "\",\"kind\":\"" + symTag( s.kind )
             + "\",\"file\":\"" + mcpdetail::jsonEscape( std::string( sqSingleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], sqRootPrefix )
                                                                                   : std::string_view( ing.files[ s.fileId ] ) ) )
             + "\",\"line\":" + std::to_string( s.line )
             + ",\"handle\":\"" + mcpdetail::jsonEscape( handleFor( ix, id ) ) + "\"}";
    };

    std::string out = "{";
    if( sqSingleRoot )
    {
        out += "\"root\":\"" + mcpdetail::jsonEscape( root ) + "\",";
    }
    out += "\"symbol\":" + symObj( f ) + ",\"calledBy\":[";
    {
        const auto* ro = g.inEdges.rowOffsets();
        const auto* ci = g.inEdges.colIndices();
        bool first = true;
        for( std::uint32_t k = ro[f]; k < ro[f + 1]; ++k )
        {
            if( !first )
            {
                out += ",";
            }
            out += symObj( ci[k] );
            first = false;
        }
    }
    out += "]";
    if( !referencingOnly )
    {
        out += ",\"calls\":[";
        bool first = true;
        for( std::uint32_t k = g.outOff[f]; k < g.outOff[f + 1]; ++k )
        {
            if( !first )
            {
                out += ",";
            }
            out += symObj( g.outTargets[k] );
            first = false;
        }
        out += "]";
    }
    // §H4 §3.4: find_symbol / find_referencing_symbols are the MCP twins of --callees / --callers, so the
    // calledBy/calls arrays are the SAME floor the CLI rows are. JSON carries no comment node, so the marker
    // travels as the key alone; the wording that explains it lives in these two verbs' tools/list
    // descriptions, which is where an MCP client reads prose.
    //
    // V3 L-6: that claim used to also name "the twinned XML surfaces", and it was only HALF true — the
    // descriptions carried the floor prose but not the counting-unit half, so a JSON caller was pointed at a
    // document that answered one of the two questions. Both halves are in the two descriptions now (mcp.h),
    // and the cross-reference to the XML surfaces is gone, because a JSON client does not read them.
    out += graphCountFloorAttrJson( g );   // M15: gauge + marker
    out += "}";
    return out;
}

// `grep` verb: parallel literal scan, each hit annotated with its enclosing symbol. V1-2:
// this payload silently served a row cap with no disclosure — and the §A1 collection
// split changed the served count (an undisclosed cap means an undisclosable change). Now the two grep
// halves run separately so the payload can say what the CLI says: total= (all collected hits), shown=,
// capped=, and hits_capped= (collection ceiling ⇒ total is a floor).
//
// Verifier N8: `page` is the request's limit/offset (mcpPageArgs, above) — grep was the only paged CLI verb
// whose MCP twin reported `capped:true` at 100 hits with NO knob to raise or walk past it, so the honest
// disclosure named a cut the caller could not do anything about. The window is the SAME pageview.h trio
// (effectiveRowCap → pageWindow → pageDisclosure) the CLI --grep applies over the same fully-collected,
// fully-sorted list, so page N here is byte-for-byte page N there. Defaulted to {} ⇒ the un-paged answer is
// byte-identical to what it was, `files`/`total`/`order` included.
// R1b (the 2026-08-12 usage mine), the CLI <enc> block's JSON twin: ONE entry per DISTINCT enclosing
// symbol NAME of the served page, first-appearance order, `callers` the distinct-caller union off the
// in-edge CSR the index already holds — zero new analysis, bounded by the page's own row cap. Row
// semantics live in search.h's grepEnclosingRows (shared with the CLI emitter); this is serialization.
// Returns "" or a leading-comma fragment the caller splices before its closing brace.
inline std::string grepEnclosingJson( const IngestResult& ing, const Graph& g, std::span<const GrepHit> hits )
{
    const std::vector<GrepEncRow> encRows = grepEnclosingRows( ing, g, hits );
    if( encRows.empty() )
    {
        return {};
    }
    std::string out = ",\"enclosing\":[";
    bool        first = true;
    for( const GrepEncRow& row : encRows )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        out += "{\"n\":\"" + mcpdetail::jsonEscape( row.chain ) + "\",\"callers\":" + std::to_string( row.callerCount );
        if( row.defCount > 1 )
        {
            out += ",\"defs\":" + std::to_string( row.defCount );
        }
        if( row.cx > 0 )
        {
            out += ",\"cx\":" + std::to_string( row.cx );
        }
        out += "}";
    }
    out += "]";
    return out;
}

// R1a, the zero-hit follow-up (shared grepZeroHitSuggestions — the CLI and the MCP verb cannot diverge):
// an honest total:0 stays, and a labeled `suggest` object teaches the two next moves in this surface's
// own spelling — `near` (did-you-mean) and the `for` verb (the grep→for conversion the mine shows never
// happens unprompted). "" for non-word-like patterns: byte-identical to the pre-R1a answer.
inline std::string grepSuggestJson( const IngestResult& ing, const std::string& pattern )
{
    const GrepZeroHitSuggestions sug = grepZeroHitSuggestions( ing, pattern, /*regex=*/false );
    if( sug.near.empty() && !sug.offerFor )
    {
        return {};
    }
    std::string out = ",\"suggest\":{\"note\":\"suggestions, not matches — hits stays an honest zero\"";
    if( !sug.near.empty() )
    {
        out += ",\"near\":\"" + mcpdetail::jsonEscape( sug.near ) + "\"";
    }
    if( sug.offerFor )
    {
        out += ",\"next_verb\":\"for\",\"next_task\":\"" + mcpdetail::jsonEscape( pattern ) + "\"";
    }
    out += "}";
    return out;
}

// §R-J: the CLI <unindexed> twin (see main.cpp's emitGrepUnindexed) — the JSON "unindexed" array, present
// only when non-empty (the same "absent means none" convention corpus_excluded/corpus_oversize already use),
// lifted out for the same reason grepEnclosingJson/grepSuggestJson above were: pure serialization of an
// already-collected list (search.h's grepCollectAux), so grepHitsJson's own body does not carry the loop.
// §R-J: the CLI unindexed_hits=/unindexed_files_scanned=/unindexed_files_skipped=/unindexed_candidates_capped=
// twins as one JSON key fragment — mirrors main.cpp's grepUnindexedAttrs (same conditions: hits= and
// scanned= unconditional, the two skip keys only when non-zero/true), lifted out for the same reason
// grepAuxJson below is. H4: unindexed_hits joins it on BOTH dialects at once — mcpclidiffcheck's LENS2 asks
// that every fact the CLI root states be present here, and a completeness attribute is exactly the class of
// fact a dialect may not drop.
inline std::string grepUnindexedKeys( const GrepAuxCollection& aux )
{
    const std::uint32_t skipped = aux.filesSkippedOversize + aux.filesSkippedBinary + aux.filesUnreadable;
    std::string          keys    = ",\"unindexed_hits\":" + std::to_string( aux.hits.size() );
    keys += ",\"unindexed_files_scanned\":" + std::to_string( aux.filesScanned );
    if( skipped > 0 )
    {
        keys += ",\"unindexed_files_skipped\":" + std::to_string( skipped );
    }
    if( aux.candidatesCapped )
    {
        keys += ",\"unindexed_candidates_capped\":true";
    }
    return keys;
}

// R-H span tiers: the CLI grepTierAttrs() twin (main.cpp), same conditions and same key names so the two
// surfaces cannot report the same run differently (mcpclidiffcheck's LENS2 fact parity). Lifted out for the
// same reason grepUnindexedKeys above was: a payload key fragment is a helper's job, not the verb body's.
inline std::string grepTierKeys( const GrepTierReport& tier )
{
    if( !tier.hasDisclosure() )
    {
        return {};
    }
    std::string keys;
    if( tier.suppressedComment > 0 )
    {
        keys += ",\"suppressed_comment\":" + std::to_string( tier.suppressedComment );
    }
    if( tier.suppressedString > 0 )
    {
        keys += ",\"suppressed_string\":" + std::to_string( tier.suppressedString );
    }
    if( std::strcmp( tier.emittedTier, "code" ) != 0 )
    {
        keys += std::string( ",\"tier\":\"" ) + tier.emittedTier + "\"";
        // M17: the CLI grepTierAttrs() twin — same condition, same name. A confidence qualifier is exactly
        // the class of fact a dialect may not drop (mcpclidiffcheck's LENS2), and an MCP-only agent has no
        // CLI to re-ask from before trusting the label.
        if( tier.unclassifiedHits > 0 )
        {
            keys += ",\"tier_partial\":true";
        }
    }
    keys += ",\"tier_parsed\":" + std::to_string( tier.tieredFileCount );
    if( tier.unclassifiedHits > 0 )
    {
        keys += ",\"tier_unclassified\":" + std::to_string( tier.unclassifiedHits );
    }
    if( tier.budgetHit != nullptr )
    {
        keys += std::string( ",\"tier_budget\":\"" ) + tier.budgetHit + "\"";
    }
    return keys;
}

// parse_degraded routing (2026-08-30, mcpgrepdegradedcheck — the CLI <f> attribute's JSON twin): the note is
// this dialect's legend channel (grepSuggestJson's own precedent), and it travels ONLY in an answer that
// emitted the key — a clean answer stays byte-identical (the same gated-clause rule the CLI legend applies to
// its parse_degraded sentence). Lifted out for the same reason grepTierKeys/grepUnindexedKeys above were: a
// payload key fragment is a helper's job, not the verb body's. The predicate is model.h's fileParseDegraded —
// the ONE rule the CLI emitter and the refusal clause already join, never a forked re-derivation.
inline std::string grepDegradedNoteJson( const IngestResult& ing, std::span<const GrepHit> hits )
{
    const bool anyParseDegraded = std::any_of( hits.begin(), hits.end(), [ & ]( const GrepHit& h ) { return fileParseDegraded( ing, h.fileId ); } );
    if( !anyParseDegraded )
    {
        return {};
    }
    return ",\"parse_degraded_note\":\"a hit carrying parse_degraded:true sits in a file whose parse holds ERROR/MISSING nodes"
           " (the skipped verb itemizes err=/err_ratio=): symbols there may be unextracted, so read an absent in on such a hit as"
           " UNKNOWN, not as file scope. Unmarked hits parsed clean, except that a file the ingest never parsed at all — doc-format,"
           " binary-sniffed, unreadable — is also unmarked, the skipped verb's unmeasured class.\"";
}

// H4 (capture-audit 2026-09-04 — lens1 F1, lens2 M3, lens8 #12): an OBJECT, not a bare array. A bare array
// is the one JSON shape that cannot carry its own disclosure, and this list needed three: how many hits it
// holds, how many it printed, and whether that was a cut. Live pre-fix, `grep … limit:3` returned 3 hits
// and 29 unindexed rows — 2,805 B for a three-row answer — because `limit` reached the indexed list only.
// The keys are the CLI element's attributes verbatim (count/shown/capped) so the two dialects state the
// same facts under the same names; `rows` holds what the window admitted.
inline std::string grepAuxJson( const std::vector<GrepAuxHit>& hits, const PageWindow& window, bool singleRoot,
                                const std::string& rootPrefix )
{
    if( hits.empty() )
    {
        return {};
    }
    const std::size_t shown = window.end - window.begin;
    std::string       out   = ",\"unindexed\":{\"count\":" + std::to_string( hits.size() )
                      + ",\"shown\":" + std::to_string( shown )
                      + ",\"capped\":" + ( shown < hits.size() ? "true" : "false" )
                      + ",\"rows\":[";
    bool first = true;
    for( std::size_t i = window.begin; i < window.end; ++i )
    {
        const GrepAuxHit& h = hits[i];
        if( !first ) { out += ","; }
        first = false;
        out += "{\"file\":\"" + mcpdetail::jsonEscape( std::string( singleRoot ? sarif::rootRelativeUri( h.path, rootPrefix ) : std::string_view( h.path ) ) )
             + "\",\"line\":" + std::to_string( h.line ) + "}";
    }
    out += "]}";
    return out;
}

// The ONE reader for the MCP `in` argument, shared by the live `grep` verb and the `batch` grep sub-query
// (wave-3 verifier P6-1/P6-2/P3-4). Two things it fixes at once:
//   · a CLOSED value set is now enforced on BOTH dialects. `in:"Any"`, `in:"all"`, `in:"comments"` used to
//     read as the default and silently return the tiered answer — in the direction that HIDES rows, which
//     is precisely why the CLI twin refuses. The "this verb has no refusal channel per-argument" rationale
//     was false: mcprefusal.h already registers the field, and the batch surface refuses loudly.
//   · `in` reaches the batch arm at all. It previously took the defaulted GrepIn::Code with no hatch.
// Absent reads as the default, as an OPTIONAL field must; only a PRESENT unknown spelling refuses.
inline std::string grepInModeFromArg( std::string_view typed, GrepIn& out )
{
    out = GrepIn::Code;
    if( typed.empty() || typed == "code" )
    {
        return {};
    }
    if( typed == "any" )
    {
        out = GrepIn::Any;
        return {};
    }
    return mcprefuse::badValueRefusal( "in", typed );
}

inline std::string grepHitsJson( const std::string& root, const std::string& pattern, McpPageArgs page = {}, GrepIn grepInMode = GrepIn::Code )
{
    const McpIndex&            ix        = getIndex( root );
    const IngestResult&        ing       = ix.ing;
    constexpr int              kRowCap   = 100;
    // R-H span tiers: the SAME filter, in the SAME position (after collection), as the CLI verb applies —
    // search.h owns the policy precisely so these two surfaces cannot answer differently. `grepInMode` is
    // the MCP `in` argument (the CLI --grep-in twin): the escape hatch has to exist here too, because an
    // MCP-only agent that reads suppressed_comment= has no CLI to re-ask from. Counters ride the payload
    // below under the CLI's own key names.
    GrepTierReport             tierReport;
    const GrepCollection       collected = grepApplySpanTiers( ing, grepCollect( ing, pattern, /*regex=*/false, /*noPrefilter=*/false ),
                                                               grepInMode, tierReport );
    const PageWindow           grepPage  = pageWindow( collected.raw.size(), effectiveRowCap( page.limit, kRowCap ), page.offset );
    const std::size_t          rowCount  = grepPage.end - grepPage.begin;
    const std::vector<GrepHit> hits      = grepEnrich( ing, std::span<const GrepRawHit>( collected.raw ).subspan( grepPage.begin, rowCount ), 0, 0 );

    // §R-J: the CLI's unindexed_files_scanned=/unindexed block twin (search.h grepCollectAux) — literal-only,
    // matching this verb. No --max-file-size equivalent on the MCP surface, so this uses the same
    // kDefaultMaxFileBytes ceiling the CLI falls back to when --max-file-size was never passed.
    const GrepAuxCollection aux = grepCollectAux( ing.crawlSkips, pattern, /*regex=*/false, kDefaultMaxFileBytes );

    // §B6 M12: the two disclosures the CLI legend carries and this payload did not. `files` is the
    // DENOMINATOR (how many distinct files the hits come from — hits sorted by file, so one pass counts
    // them), and `order` states the ORDER, because the rows ARE reordered and a JSON array reads as
    // "whatever order the tool found them in" unless it says otherwise (§A10.3, the same reason whereis
    // states its ordering in full). Both are facts about this answer, so they ride in the answer.
    std::uint32_t prevFile = UINT32_MAX;
    std::size_t   filesMatched = 0;
    for( const GrepRawHit& h : collected.raw )
    {
        if( h.fileId != prevFile )
        {
            ++filesMatched;
            prevFile = h.fileId;
        }
    }

    // N8: shown/capped (+ total/has_more/next_offset/offset/limit when paging) come from pageview.h's ONE
    // disclosure under its JSON syntax row, not from a hand-written pair that would be a second vocabulary.
    // `total` is emitted here only when the disclosure will NOT — un-paged it is grep's own row count and
    // must stay (the CLI's <grep hits="T"> twin); paged, the disclosure carries it, and JSON cannot spell
    // the same key twice the way the CLI's XML root spells both hits= and total=.
    char       pagebuf[ kPageDisclosureCap ];
    const bool isPaging = page.limit > 0 || page.offset > 0;

    // T1: the completeness claim, the SAME four conditions as the CLI emitter (main.cpp's emitGrepReport)
    // minus the regex arm — this verb is literal-only, so every scan is a full end-to-end read. Appended
    // after hits_capped so the historic key order other gates read is byte-untouched; absent when any
    // condition fails (the floor vocabulary already covers partial answers).
    // R-H adds the tier arm the CLI emitter also adds: a listing that held comment/string rows back did not
    // print every hit it found, so it may not claim to be exhaustive.
    const bool scanExhaustive  = collected.cleanScan();
    const bool windowWhole     = grepPage.begin == 0 && grepPage.end == collected.raw.size();
    const bool nothingHeldBack = tierReport.suppressedComment == 0 && tierReport.suppressedString == 0;

    // R-H: the CLI tierAttr twin (helper above) — empty when nothing was held back.
    const std::string tierKeys = grepTierKeys( tierReport );

    // G1 (2026-08-15 harvest, report-memgraph §F6): `file` is root-relative when this is a single-root
    // index (ing.realPaths empty — the same condition the CLI emitter gates on), reusing sarif.h's strip
    // rather than re-deriving it (grepCollect's own rule: shared logic so the two surfaces cannot diverge).
    // Multi-root already carries the compact `<label>/<relpath>` identity untouched.
    const bool        singleRootJ = ing.realPaths.empty();
    const std::string rootPrefixJ = singleRootJ ? sarif::rootPrefixOf( root ) : std::string();
    const auto         pathForJ   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return singleRootJ ? sarif::rootRelativeUri( ing.files[ fileId ], rootPrefixJ ) : std::string_view( ing.files[ fileId ] );
    };

    std::string out = "{\"pattern\":\"" + mcpdetail::jsonEscape( pattern )
                    // G1: mirrors the CLI <grep root="…"> — same condition (singleRootJ), same fact, right
                    // after pattern like the CLI's attribute order (mcpclidiffcheck.sh's LENS2 fact-parity).
                    + ( singleRootJ ? ( "\",\"root\":\"" + mcpdetail::jsonEscape( root ) + "\"" ) : "\"" )
                    + ",\"files\":" + std::to_string( filesMatched )
                    + ( isPaging ? std::string{} : ( ",\"total\":" + std::to_string( collected.raw.size() ) ) )
                    + pageDisclosure( pagebuf, sizeof( pagebuf ), rowCount, collected.raw.size(), grepPage.end,
                                      page.limit, page.offset, /*discloseCap=*/true, kJsonPageSyntax )
                    + ",\"hits_capped\":" + ( collected.isBudgetReached ? "true" : "false" )
                    + ( scanExhaustive && windowWhole && nothingHeldBack ? ",\"complete\":true" : "" )
                    + tierKeys
                    // G4 (2026-08-15 harvest, report-ugrep §F6): the CLI's corpus_excluded=/corpus_oversize=
                    // twins — present only when non-zero, same condition as the CLI emitter.
                    + ( ing.crawlSkips.excludedFiles > 0 ? ( ",\"corpus_excluded\":" + std::to_string( ing.crawlSkips.excludedFiles ) ) : std::string() )
                    + ( !ing.skippedOversize.empty() ? ( ",\"corpus_oversize\":" + std::to_string( ing.skippedOversize.size() ) ) : std::string() )
                    // §R-J: unindexed_files_scanned=/unindexed_files_skipped=/unindexed_candidates_capped=
                    // (helper above) — mcpclidiffcheck's LENS2 fact-parity arm requires scanned= at minimum.
                    + grepUnindexedKeys( aux )
                    + ",\"order\":\"SOURCE files before test/bench files before docs, then path and line\""
                    + ",\"hits\":[";
    bool first = true;
    for( const GrepHit& h : hits )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        // in= honesty (G1): omit the key entirely rather than emit "in":"" when no symbol encloses the hit
        // — an absent key reads as "not attributed", never "file scope" (the CLI's matching `in=` omission).
        out += "{\"file\":\"" + mcpdetail::jsonEscape( std::string( pathForJ( h.fileId ) ) ) + "\",\"line\":" + std::to_string( h.line );
        if( !h.enclosing.empty() )
        {
            out += ",\"in\":\"" + mcpdetail::jsonEscape( h.enclosing ) + "\"";
        }
        // parse_degraded routing (2026-08-30, mcpgrepdegradedcheck — the CLI <f> attribute's JSON twin):
        // this dialect has no file rows to hang the fact on, so it rides each hit row instead.
        if( fileParseDegraded( ing, h.fileId ) )
        {
            out += ",\"parse_degraded\":true";
        }
        out += "}";
    }
    out += "]";
    // parse_degraded's in-band definition (helper above) — "" on a clean answer.
    out += grepDegradedNoteJson( ing, std::span<const GrepHit>( hits ) );
    // §R-J: the CLI <unindexed> twin (helper above) — appended AFTER "hits" for the same reason the R1
    // block below is: existing key-order-sensitive gates read up through "hits" first.
    // H4: the SAME window the indexed list obeyed, over this list's own length (the CLI emitter's auxPage
    // twin) — `limit` reached only the hits array before, so a three-row page shipped 29 unindexed rows.
    out += grepAuxJson( aux.hits, pageWindow( aux.hits.size(), effectiveRowCap( page.limit, kRowCap ), page.offset ),
                        singleRootJ, rootPrefixJ );
    // R1 (the 2026-08-12 usage mine): the CLI <enc>/<suggest> twins, appended AFTER "hits" so the
    // historic key order three other gates read (files,total,shown,capped) is byte-untouched.
    out += grepEnclosingJson( ing, ix.g, std::span<const GrepHit>( hits ) );
    if( collected.raw.empty() )
    {
        out += grepSuggestJson( ing, pattern );
    }
    out += "}";
    return out;
}

// `cochange` verb: the files that historically change together with `file` (the lockstep partners to
// also edit). "" if the file isn't found. Shares cochangePartners() with the --cochange CLI.
inline std::string cochangePartnersJson( const std::string& root, const std::string& file )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const std::uint32_t fid = resolveFileSuffix( ing, file );
    if( fid == UINT32_MAX )
    {
        return {};
    }
    std::uint32_t                commits = 0;
    const std::vector<CoPartner> ps      = cochangePartners( root, ing, file, commits );
    // §P8 vocabulary: the JSON sibling of the XML at= anchor the CLI --cochange now carries — same spelling
    // and same null-on-a-non-git-root convention main.cpp's --quality-delta --json already established.
    const std::string atVal  = gitstamp::stampAt( root );
    const std::string atJson = atVal.empty() ? std::string( "null" ) : ( "\"" + atVal + "\"" );
    // R-E fix (2026-08-19): root-relative file paths + the "root" key, the JSON siblings of the root= the CLI
    // --cochange now carries. The first R-E landing converted the CLI arm alone, so the two dialects of one
    // answer spelled their paths differently — the same divergence the at= note above exists to prevent.
    const bool         ccSingleRoot = ing.realPaths.empty();
    const std::string  ccRootPrefix = ccSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const auto         ccRel        = [ & ]( std::uint32_t f ) -> std::string
    { return std::string( ccSingleRoot ? sarif::rootRelativeUri( ing.files[f], ccRootPrefix ) : std::string_view( ing.files[f] ) ); };
    std::string out = "{";
    if( ccSingleRoot )
    {
        out += "\"root\":\"" + mcpdetail::jsonEscape( root ) + "\",";
    }
    out += "\"file\":\"" + mcpdetail::jsonEscape( ccRel( fid ) ) + "\",\"commits\":" + std::to_string( commits )
         + ",\"at\":" + atJson + ",\"partners\":[";
    bool first = true;
    for( const CoPartner& p : ps )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        char deg[ 16 ];  std::snprintf( deg, sizeof( deg ), "%.2f", p.deg );
        // §A9.3: the JSON sibling of the XML dep_capable= tell — surprising is false for a pair that could
        // never have carried a static dependency, and dep_capable says WHY it is false.
        out += "{\"file\":\"" + mcpdetail::jsonEscape( ccRel( p.fileId ) ) + "\",\"together\":" + std::to_string( p.together )
             + ",\"deg\":" + deg + ",\"surprising\":" + ( p.surprising ? "true" : "false" )
             + ",\"dep_capable\":" + ( p.depCapable ? "true" : "false" ) + "}";
    }
    out += "]}";
    return out;
}

// `memory_recall` verb: the most relevant DOCS (memory notes / design docs) for a task, full bodies,
// budgeted. Goes through recall.h's recallFor — the SAME rank-then-build call the CLI --recall verb makes,
// arguments and all — so the two front doors of one verb cannot rank a query differently. They did until
// this landed: this call site scored with `lexicalScores( ix.ing, …, task )`, i.e. pathFieldDefaultW 0 and
// no root prefix, while the CLI passed 1 and the prefix, under the comment "Shares lexicalScores" that used
// to sit here. A doc found only by its PATH was retrieved by the CLI and reported "no relevant documents"
// over MCP. Registered in docs/EVALS.md §"--recall ranks by where the repo sits on disk"; gated by
// test/recallparitycheck.sh. Returns a plain-text bundle. `redact` masks credential shapes in the recalled
// doc bodies (A3-F3 — same seam contract as the CLI --recall).
inline std::string recallText( const std::string& root, const std::string& task, int k, std::size_t maxBytes, RedactCounts* redact = nullptr )
{
    const McpIndex& ix = getIndex( root );
    // docs (markdown) only; R-R root-relative separators AND root-relative path ranking — both from this
    // one rootArg, exactly as the CLI derives its own. Empty for a multi-root index, whose ing.files
    // already hold the labelled root-relative spelling.
    return recallFor( ix.ing, ix.g.outOff, ix.g.outTargets, task, k, maxBytes, redact,
                      ix.ing.realPaths.empty() ? std::string_view( root ) : std::string_view() ).text;
}

// `situational_awareness(diff)` verb (S5-D): for a DIFF — an explicit changed-file list in `diff`/`files`, OR
// (when neither is given) the working-tree `git diff HEAD` — return the 5 facts as a JSON object:
//   blast_radius   — files transitively reaching the changed set (with dependent-symbol count)
//   tests_to_run   — the test files among the blast radius
//   forgotten      — files that co-changed with the diff in past commits but are NOT in this diff
//   hotspot_alert  — changed files with high cx×churn (Σ cognitive complexity × commits touching the file)
//   modules_touched— the distinct top-level directories the diff hit
// Hand-rolled JSON (same jsonEscape + manual string-building as the other verbs). `diffOrEmpty` empty ⇒ git
// diff. Returns "" ONLY when git is genuinely unavailable (not a git repo / git not installed) — a clean
// working tree (zero changed files) returns a VALID result with all-empty arrays and a note field.
// H6 (lens 6 F1): the MCP twin of --situ's FILE-list refusal. `situational_awareness{files:"src/nosuch.h"}`
// used to answer all-empty arrays with a green `_fresh: ok` — the same false zero the CLI arm printed, and
// the worse of the two, because a JSON result reads as an ANSWER to every caller that only checks for an
// `error` key. Same text as the CLI (situ.h::fileListRefusalText) with the MCP field name in place of the
// flag. Empty ⇒ the list is fine (or absent, i.e. the git-diff default).
inline std::string situationFileListRefusal( const std::string& root, const std::string& diffOrEmpty )
{
    if( diffOrEmpty.empty() )
    {
        return {};
    }
    const IngestResult& ing = getIndex( root ).ing;
    return fileListRefusalText( ing, "", "files", root, diffOrEmpty, changedMaskFromListChecked( ing, diffOrEmpty ) );
}

inline std::string situationDiffJson( const std::string& root, const std::string& diffOrEmpty )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;

    std::vector<char> changed;
    bool isCleanTree = false;
    if( !diffOrEmpty.empty() )
    {
        changed = changedMaskFromList( ing, diffOrEmpty );
    }
    else
    {
        auto [ mask, ok ] = gitDiffChangedMask( root, ing );
        if( !ok )
        {
            return {}; // git unavailable (not a repo) → caller reports error
        }
        changed = std::move( mask );
        // ok=true + all-zero mask = clean working tree — fall through to computeSituationFacts which returns
        // all-empty arrays; set isCleanTree so we can add an explanatory note to the JSON result.
        const bool anyChanged = std::any_of( changed.begin(), changed.end(), []( char c ) { return c != 0; } );
        isCleanTree = !anyChanged;
    }

    const SituationFacts facts = computeSituationFacts( root, ing, ix.g, changed );

    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= carries (sarif.h) — the
    // CLI text twin (situ.h::writeSituation) states the SAME fact on its own leading "root: …" line.
    const bool         situJSingleRoot = ing.realPaths.empty();
    const std::string  situJRootPrefix = situJSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const auto          situJPathRel   = [ & ]( std::uint32_t f ) -> std::string_view
    {
        return situJSingleRoot ? sarif::rootRelativeUri( ing.files[f], situJRootPrefix ) : std::string_view( ing.files[f] );
    };

    const auto fileObj = [ & ]( std::uint32_t f ) -> std::string
    { return std::string( "{\"file\":\"" ) + mcpdetail::jsonEscape( std::string( situJPathRel( f ) ) ) + "\"}"; };

    // §B6 M11: the run= hint index, from the SAME source --affected/--situ/--test-gate/--pr-context read
    // (testmap.h). runFieldJson is that header's JSON call shape, so "absent means NOT DERIVABLE" — the
    // load-bearing half of the rule — is decided in one place for every emitter rather than re-decided here.
    const TestRunnerIndex runners( ing );
    const auto            jsonEsc = []( std::string_view sv ) { return mcpdetail::jsonEscape( std::string( sv ) ); };

    // M10: this verb reads git (the diff itself, plus an 18-month co-change mine below) and, before this
    // fix, carried no anchor at all — same gap the CLI text twin (writeSituation) had. "at":null (never a
    // fake sha) on a non-git root, mirroring writeTestGateReportJson's own at= convention in this file.
    const std::string situJAtVal  = gitstamp::stampAt( root );
    const std::string situJAtJson = situJAtVal.empty() ? std::string( "null" ) : ( "\"" + situJAtVal + "\"" );

    std::string out = "{\"at\":" + situJAtJson + ",";
    if( situJSingleRoot )
    {
        out += "\"root\":\"" + mcpdetail::jsonEscape( root ) + "\",";
    }
    out += "\"changed_files\":[";
    {
        bool first = true;
        for( std::uint32_t f : facts.changed )
        {
            if( !first )
            {
                out += ",";
            }
            first = false;
            out += fileObj( f );
        }
    }

    // §B6 M11: each blast-radius row carries the dependent-SYMBOL count that already ORDERS this list. The
    // payload used to emit {"file":...} alone, so the agent got a ranked blast radius with no magnitude and
    // could not tell a file contributing 300 dependent symbols from one contributing 1 — while the CLI text
    // report has printed "(N dependent symbols)" on every such line all along.
    out += "],\"blast_radius\":[";
    {
        bool first = true;
        for( std::size_t i = 0; i < facts.blastRadius.size(); ++i )
        {
            if( !first )
            {
                out += ",";
            }
            first = false;
            out += "{\"file\":\"" + mcpdetail::jsonEscape( std::string( situJPathRel( facts.blastRadius[i] ) ) )
                 + "\",\"dependent_symbols\":" + std::to_string( facts.blastDependents[i] ) + "}";
        }
    }

    // §B6 M11: each test row carries its run= hint. This verb hands the agent an OBLIGATION ("run these")
    // and was the one emitter of the five that withheld the command, so the obligation could not be
    // discharged without guessing a runner. An ABSENT run field means NOT DERIVABLE, never a guessed suite
    // command — that rule lives in testmap.h's runHint and is not re-decided here.
    out += "]";
    out += graphCountFloorAttrJson( ix.g );   // H5/M15: blast_radius[].dependent_symbols is read off the name-based CSR — a floor, with the gauge
    out += ",\"tests_to_run\":[";
    {
        bool first = true;
        for( std::uint32_t f : facts.tests )
        {
            if( !first )
            {
                out += ",";
            }
            first = false;
            out += "{\"test\":\"" + mcpdetail::jsonEscape( std::string( situJPathRel( f ) ) ) + "\"" + runFieldJsonDisclosed( runners, f, jsonEsc ) + "}";
        }
    }

    out += "],\"forgotten\":[";
    {
        bool first = true;
        for( const auto& [ f, deg ] : facts.forgotten )
        {
            if( !first )
            {
                out += ",";
            }
            first = false;
            char d[ 16 ];  std::snprintf( d, sizeof( d ), "%.2f", deg );
            out += "{\"file\":\"" + mcpdetail::jsonEscape( std::string( situJPathRel( f ) ) ) + "\",\"cochange_degree\":" + d + "}";
        }
    }

    out += "],\"hotspot_alert\":[";
    {
        bool first = true;
        for( const auto& [ f, score ] : facts.hotspots )
        {
            if( !first )
            {
                out += ",";
            }
            first = false;
            out += "{\"file\":\"" + mcpdetail::jsonEscape( std::string( situJPathRel( f ) ) ) + "\",\"score\":" + std::to_string( score ) + "}";
        }
    }

    out += "],\"modules_touched\":[";
    {
        bool first = true;
        for( const std::string& m : facts.modulesTouched )
        {
            if( !first )
            {
                out += ",";
            }
            first = false;
            out += "\"" + mcpdetail::jsonEscape( m ) + "\"";
        }
    }
    out += "]";

    // §M9 (W3FIX): the §B7.3 blind-spot disclosure the XML --situ prints under its [2] section, and which
    // --test-gate already carries in BOTH dialects. This verb hands the agent the same tests_to_run obligation
    // off the same traversal and disclosed nothing, so an empty array read as "nothing tests this" rather than
    // "nothing that is a CALL EDGE tests this" — a shell harness runs the compiled binary as a subprocess,
    // which is not an edge. Same counter, same source of truth (testmap.h::scriptGatesUnmodelledCount) and the
    // same key name writeTestGateReportJson uses, so this is a disclosure the dialects already shared — never
    // a second number.
    out += ",\"script_gates_unmodelled\":" + std::to_string( scriptGatesUnmodelledCount( ing ) );

    // clean working tree (git diff HEAD returned 0 files) — append a note so callers can distinguish this
    // valid-but-empty result from a populated one, mirroring how the CLI --situ says "0 changed files".
    if( isCleanTree )
    {
        out += ",\"note\":\"0 changed files — working tree is clean (git diff HEAD returned nothing to analyze)\"";
    }

    out += "}";
    return out;
}

// The @FILE:LINE rebind the NAME-matching scan verbs' payload fns share (2026-08-30 decision round): a
// resolvable line-seed's ONE innermost enclosing definition — the SEED's own def, exactly the CLI twin's
// resolveAllByNameQualified @-tier semantics, never the bare-name union (for `owners` the union's
// lowest-id pick could name the WRONG file). kNoNode when sym is not a seed, or the seed faults — the
// dispatch guards (qualifiedSelectorRefusal) refuse faulted seeds upstream with the shared at-diagnosis.
inline NodeId atSeedDefOr( const IngestResult& ing, std::string_view sym )
{
    if( sym.empty() || sym.front() != '@' )
    {
        return kNoNode;
    }
    const AtSeed seed = resolveAtSeed( ing, sym.substr( 1 ) );
    return seed.fault == AtFault::None ? seed.chain.back() : kNoNode;
}

// `mentions` verb: which DOCS (markdown plans/designs) name this code symbol in a `backtick` — the doc↔code
// link (out of the call graph). Shares g.mentions with the --mentions CLI.
// An @FILE:LINE line-seed REBINDS via atSeedDefOr (its contract above) and the answer discloses the
// rebound name as "sym" beside the as-typed "symbol" echo.
inline std::string mentionsJson( const std::string& root, const std::string& symbol )
{
    const McpIndex&           ix      = getIndex( root );
    const IngestResult&       ing     = ix.ing;
    const NodeId              seedDef = atSeedDefOr( ing, symbol );
    if( seedDef == kNoNode && !symbol.empty() && symbol.front() == '@' )
    {
        return {}; // faulted seed — refused upstream; this arm only defends dispatch drift
    }
    const std::string         seedSym = seedDef == kNoNode ? std::string() : ing.symbols[ seedDef ].name;
    const std::vector<NodeId> defs    = seedDef == kNoNode ? resolveAllByName( ing, symbol )
                                                           : std::vector<NodeId>{ seedDef };
    if( defs.empty() )
    {
        return {};
    }
    std::vector<NodeId> docs;
    for( NodeId d : defs )
    {
        if( d < ix.g.mentions.size() )
        {
            for( NodeId dn : ix.g.mentions[d] )
            {
                docs.push_back( dn );
            }
        }
    }
    std::sort( docs.begin(), docs.end() );  docs.erase( std::unique( docs.begin(), docs.end() ), docs.end() );

    // §A8.4 (same fix as CLI --mentions): one entry per FILE via the shared collapse — the old payload
    // emitted one entry per markdown SECTION, duplicating "file" values up to 3x. docs=/sections= mirror
    // the XML root's disclosures; mentions= and l= mirror the XML row attrs.
    const std::vector<MentionFileRow> fileRows = collapseMentionsToFileRows( ing, docs );
    // R-E fix (2026-08-19): root-relative "file" values + the "root" key — the JSON siblings of the root=
    // the CLI --mentions now carries. Converted with the CLI arm this time, not one release behind it.
    const bool         mnSingleRoot = ing.realPaths.empty();
    const std::string  mnRootPrefix = mnSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    std::string out = "{";
    if( mnSingleRoot )
    {
        out += "\"root\":\"" + mcpdetail::jsonEscape( root ) + "\",";
    }
    out += "\"symbol\":\"" + mcpdetail::jsonEscape( symbol ) + "\",";
    if( !seedSym.empty() )
    {
        out += "\"sym\":\"" + mcpdetail::jsonEscape( seedSym ) + "\","; // the @-seed's rebound definition name
    }
    out += "\"docs\":" + std::to_string( fileRows.size() )
         + ",\"sections\":" + std::to_string( docs.size() ) + ",\"files\":[";
    bool first = true;
    for( const MentionFileRow& row : fileRows )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        out += "{\"file\":\"" + mcpdetail::jsonEscape( std::string( mnSingleRoot ? sarif::rootRelativeUri( ing.files[ row.fileId ], mnRootPrefix )
                                                                                : std::string_view( ing.files[ row.fileId ] ) ) )
             + "\",\"mentions\":" + std::to_string( row.mentions ) + "}";
    }
    out += "]}";
    return out;
}

// `for` verb: task lens — the BM25/--for ranked, signatures-only inventory of building blocks
// relevant to `task`, framed for reuse. Reuses the warm McpIndex + the same lexicalScores +
// packSignatures/packLego/packCompose pipeline the CLI --for uses; captured via open_memstream.
// Returns the full <ctx>…</ctx> XML as a string (matches G4 — valid XML document). "for" is a
// C++ keyword so the function is named forTaskText(). `redact` masks credential shapes in the
// emitted doc comments (A3-F3 — same seam contract as the CLI --for); null under --no-redact.
//
// ── NO CAP PARAMETER, DELIBERATELY (round-4 finding F-03) ───────────────────────────────────────────
// This function used to take `int topK` and both call sites — the `for` dispatch arm and the `batch`
// sub-verb — fed it the SERVER-WIDE `--top-k`, whose default is 200. That is the ranked MAP's row cap; the
// --for lens is documented to ignore it (cli.h honorsTopK) and the CLI accordingly serves a 40-symbol head.
// So the `: 40` fallback was dead code and every MCP `for` call ran a 5x wider candidate pool than its CLI
// twin — dropped_positive="169" vs "11" on the same task over this repo, plus a substantially different
// served symbol set. The `for` tool schema exposes no cap either, so no argument could reach the CLI's
// behavior. The parameter is GONE rather than defaulted: a knob only ever fed the wrong value is not fixed
// by giving it a better default, and removing it is what makes the two dialects unable to drift again.
inline std::string forTaskText( const std::string& root, const std::string& task, RedactCounts* redact = nullptr )
{
    const McpIndex&          ix        = getIndex( root );
    const IngestResult&      ing       = ix.ing;
    // Routing is the DEFAULT here, exactly as for the CLI --for: a deterministic confidence-gated
    // query-shape classifier picks name-exact vs subtoken+body BM25, so an identifier query lands the
    // symbol (recall@1 ~99% vs ~77% plain) while conceptual queries keep the subtoken+body behavior
    // (lexical.h chooseForRanker). MCP-only agents get the same optimization the CLI ships.
    const RouteChoice        rc        = chooseForRanker( ing, task );
    // NOT const: LB-A's relevance floor narrows it below, once every boost has landed on lensRank. The
    // MaxScore pruning bound two stanzas down consumes the PRE-floor value, which is the safe direction —
    // a bound computed for a larger K can only keep more candidates, never fewer.
    int                      forTopN   = kForLensDefaultTopN;   // F-03: the ONE cap, shared with the CLI lens (serialize.h)
    // H2 (B0 r2): the MCP `for` bundle reads only the top-forTopN of this rank plus every interface
    // (packLego) — same exact MaxScore pruning contract as the CLI --for (byte-identical output).
    std::vector<char> ifaceExact( ing.symbols.size(), 0 );
    for( std::size_t i = 0; i < ix.g.implementors.size() && i < ifaceExact.size(); ++i )
    {
        if( !ix.g.implementors[i].empty() )
        {
            ifaceExact[i] = 1;
        }
    }
    // Query SHAPE + §P4 tier de-prioritization — same classifier, same multiplier, same order (before the
    // mention anchor) as the CLI --for. This dialect always routes, so the shape is always asked for and
    // the disclosure always has a route= to ride in.
    const queryshape::Verdict shape   = queryshape::classify( task );
    const std::vector<float>  tierMul = rankTierSymbolMultipliersShaped( ing, shape.fires() );
    // deep-tail: this bundle now serves the file-grain tail, a full-distribution consumer — the H2
    // MaxScore prune bound is 0 (exhaustive) here for the same reason the CLI --for passes
    // fullDistribution (a pruned tail would make total= mode-dependent and its order incomplete).
    std::vector<float> lensRank  = ( rc.which == LexMode::NameExact )
                                       ? lexicalScoresNameExactRanked( ing, task, &tierMul )
                                       : lexicalScoresTiered( ing, ix.g.outOff, ix.g.outTargets, task, /*topKBound=*/0, &ifaceExact, &tierMul );

    // B8 (query-mention anchoring): same default-on contract as the CLI --for — files / dotted modules /
    // Scope.symbols literally NAMED in the task text are lifted to just below the top hit (the measured #1
    // competitor-win bucket; bench/headtohead). Pure string extraction + in-memory matching (no I/O),
    // inert (byte-identical) when the text names nothing indexed. RIPWIRE_NO_MENTION=1 (the shared
    // ablation env) disables it here too. Runs BEFORE the co-change prior, same as the CLI.
    std::string mentionNote;
    if( !std::getenv( "RIPWIRE_NO_MENTION" ) )
    {
        MentionBoostInfo mentionInfo;
        if( applyMentionBoost( ing, task, lensRank, &mentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [mention anchor: %u file%s + %u symbols named in the task, score lifted to within 5%% of the top score]",
                           mentionInfo.fileCount, mentionInfo.fileCount == 1 ? "" : "s", mentionInfo.symbolCount );
            mentionNote = nb;
        }
    }

    // B3 (co-change prior boost) — OPT-IN, EXPERIMENTAL, same contract as CLI --cochange-boost: files that
    // historically change WITH the top-ranked files promote their best symbols into the lower bundle (never
    // displacing the seeds). Default OFF — honest numbers in cli.h: held-out multi-file +0.0pp on Python
    // LocBench at warm p50 +19%; revisit on the C++ history eval. Mined per request (one `git log -500
    // --name-only` popen; the .git walk-up guard makes non-git roots free) rather than cached on McpIndex:
    // history moves when HEAD moves, which the mtime/content staleness stamp does not watch. The MCP verb
    // has no per-call flags — RIPWIRE_COCHANGE=1 (the shared opt-in env) enables it here.
    // Inert without usable history (depth-1 / non-git ⇒ support threshold unreachable ⇒ byte-identical output).
    std::string boostNote;
    if( std::getenv( "RIPWIRE_COCHANGE" ) && hasEnclosingGitRepo( root ) )
    {
        const auto coSets = gitRecentCommitFileSets( root, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit );
        CoBoostInfo boostInfo;
        if( !coSets.empty() && applyCoChangeBoost( ing, coSets, lensRank, &boostInfo ) )
        {
            char nb[ 200 ];
            std::snprintf( nb, sizeof( nb ), " [cochange boost: promoted %u symbols in %u files that historically change with the top seeds (last %u commits)]",
                           boostInfo.boostedSymbolCount, boostInfo.boostedFileCount, kCoBoostCommitWindow );
            boostNote = nb;
        }
    }

    // R5 (doc-mention surfacing) — same default-on, route-agnostic contract as the CLI --for: a doc
    // that names one of the task's top-resolved symbols in a `backtick` (g.mentions, the same edges the
    // `mentions` MCP verb reads) is lifted into the bundle, strictly below that symbol's own score.
    // RIPWIRE_NO_DOC_MENTION=1 disables it here too (the shared ablation env, same as RIPWIRE_NO_MENTION).
    std::string docMentionNote;
    if( !std::getenv( "RIPWIRE_NO_DOC_MENTION" ) )
    {
        DocMentionBoostInfo docMentionInfo;
        if( applyDocMentionBoost( ix.g, lensRank, &docMentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [doc mentions: %u doc%s discussing %u top-ranked symbol%s surfaced]",
                           docMentionInfo.docCount, docMentionInfo.docCount == 1 ? "" : "s",
                           docMentionInfo.anchorCount, docMentionInfo.anchorCount == 1 ? "" : "s" );
            docMentionNote = nb;
        }
    }

    // LB-A (r10 §5) — THE RELEVANCE FLOOR, the CLI --for's own call (serialize.h relevanceFloorCut): one
    // bundle-composition contract may not have two behaviours. lensRank is final at this point.
    auto [ flooredTopN, floorNote ] = relevanceFloorCut( lensRank, forTopN );
    forTopN = flooredTopN;

    const std::vector<char>  impure    = computeImpure( ing, ix.g );

    // fan-in counts: in-degree per node (how many symbols call this one — the "reuse" metric)
    const std::size_t S = ing.symbols.size();
    std::vector<std::uint32_t> fanIn( S, 0 );
    {
        const auto* ro = ix.g.inEdges.rowOffsets();
        const auto* ci = ix.g.inEdges.colIndices();
        for( std::size_t i = 0; i < S; ++i )
        {
            fanIn[i] = ro[i + 1] - ro[i];   // in-degree = callers of symbol i
        }
    }

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {};
    }

    // G4: task and rc.reason are agent-controlled and land verbatim in an XML comment below — a "-->" run
    // would close the comment early and inject XML, and any "--" run alone breaks strict xmllint parsing.
    // W3FIX M3: the dash collapse was the ONLY scrub here, so an agent-supplied C0 byte, invalid UTF-8
    // sequence or newline still broke the document — xmlCommentText (serialize.h) is the ONE scrub for all
    // three, shared with the CLI --for twin so the two dialects cannot diverge on hostile input.
    const std::string safeTask = xmlCommentText( task );
    // L1 (density audit 2026-08-08): rc.reason no longer needs a comment-scrubbed copy — it rides ONLY in
    // the route= attribute (ctxRootOpen escapes it), same single-copy contract as the CLI --for twin
    // (test/routeoncecheck.sh).
    // H1 (B0 r2): the MCP `for` bundle enforces the same GLOBAL default payload budget as the CLI --for
    // (serialize.h kForPayloadBudgetBytes). Lego + compose are rendered into memory FIRST so the <sigs>
    // budget is the exact remainder; emission ORDER is unchanged (header, sigs, lego, compose, </ctx>),
    // and when nothing trims the bytes are identical to the pre-H1 path.
    // ── verifier FINDING E4 (2026-08-19): the CLI --for answered with `src/main.cpp` and disclosed root=;
    //    its MCP twin answered the same question with the absolute path and disclosed nothing. Same
    //    single-root condition, the same rootArg threaded into the same three emitters the CLI passes it to
    //    (ctxRootOpen / packSignatures / packLego), and the same shared legend clause on the tail of the
    //    header comment — so the two dialects stay byte-consistent on what they say and what they explain.
    const std::string_view flRootArg = ing.realPaths.empty() ? std::string_view( root ) : std::string_view();
    // T3 disclosure (test/fordisclosurecheck.sh #4): this verb serves the LAZY-BODY posture — signatures
    // plus fetch_body handles, never inline bodies — and says so the way the CLI's auto bundle does:
    // bundle= on the ctx root plus a legend clause naming the way to a body. The attribute-free root is
    // reserved for the caller-CHOSEN opt-out (--signatures-only, pre-T3 byte-identical by registration);
    // a posture the TOOL chose for the caller must be disclosed, or an MCP agent reading this bundle
    // cannot tell "no bodies exist for this task" from "this dialect never serves them".
    std::string rootOpenStr = ctxRootOpen( task, " [routed: " + rc.reason + shapeDemotionNote( shape ) + "]", flRootArg );   // §B1.7: same root attrs as the CLI twin
    if( !rootOpenStr.empty() && rootOpenStr.back() == '>' )
    {
        rootOpenStr.insert( rootOpenStr.size() - 1, " bundle=\"sigs\"" );
    }
    std::string headerStr = rootOpenStr
                          + "<!-- ripwire lens for \"" + safeTask + "\"" + mentionNote + boostNote + docMentionNote + floorNote
                          + ": reusable building blocks (cx=complexity, in=reuse-count) — prefer composing/reusing these over reimplementing"
                            "; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb"
                          + std::string( rw::kForFileTailLegend )   // deep-tail: r= + <tail> definitions, the CLI twin's exact clause (sigs-charge-exempt below)
                          + " -->"
                          + rw::forRootRelPathsLegendShort( !flRootArg.empty() );   // W3-S item 5: closes the gap this comment used to record
    // W3-S item 5 (2026-08-19): both --for dialects now carry rw::kForRootRelPathsLegendShort (graphlegend.h)
    // — the SAME short spelling, appended here exactly as the CLI twin (forLensHeaderText, main.cpp) does,
    // so byte-consistency between the two dialects (this file's own standing contract) still holds. See that
    // function's own comment for why a shorter wording, not the shared 18-verb kRootRelPathsLegend, closes
    // this gap: this lens's ceiling is the one place the full 159 B clause measurably does not fit.
    const auto renderToString = [ ]( auto&& emitFn ) -> std::string { return captureXml( emitFn ); };
    // THE BUNDLE'S RESOLVED SURFACE (top-N by lensRank — the set <sigs> selects), shared by the compose
    // view, the B6.3 route view and (§P3) the <lego> scope filter. Same order the CLI --for uses.
    std::vector<NodeId> lensSurfaceIds( S );
    for( NodeId i = 0; i < NodeId( S ); ++i )
    {
        lensSurfaceIds[i] = i;
    }
    std::sort( lensSurfaceIds.begin(), lensSurfaceIds.end(),
               [ &lensRank ]( NodeId a, NodeId b ) { return lensRank[a] != lensRank[b] ? lensRank[a] > lensRank[b] : a < b; } );   // id tiebreak → deterministic (most lens scores tie at 0)
    lensSurfaceIds.resize( std::min<std::size_t>( std::size_t( forTopN ), S ) );

    // §P3: same scope + identity the CLI --for embeds — the MCP bundle must not carry wider scope (interfaces
    // this task never reached) or less identity (p= on every row) than its CLI twin.
    std::vector<std::vector<NodeId>> legoScoped = legoImplementorsOnSurface( ing, ix.g.implementors, lensSurfaceIds );
    std::string legoStr = renderToString( [ & ]( std::FILE* m2 ) { packLego( m2, ing, legoScoped, lensRank, 12, redact, &impure, kNoNode, /*withPaths=*/true, flRootArg ); } );
    std::string composeStr, routeStr;
    if( !ix.g.composeEdges.empty() )
    {
        composeStr = renderToString( [ & ]( std::FILE* m2 )
                                     { packCompose( m2, ing, ix.g.composeEdges, lensSurfaceIds ); } );
    }
    if( !ix.g.routeEdges.empty() )
    {
        routeStr = renderToString( [ & ]( std::FILE* m2 )
                                   { packRoutes( m2, ing, ix.g.routeEdges, lensSurfaceIds ); } ); // B6.3
    }
    // deep-tail: the tail legend's bytes are exempt from the sigs charge, exactly as the CLI twin exempts
    // them — charging a disclosure against the ranked head is what the D2/confidence precedents forbid.
    const std::size_t fixedBytes = headerStr.size() - rw::kForFileTailLegend.size()
                                 + legoStr.size() + composeStr.size() + routeStr.size() + 6;   // + "</ctx>"
    const std::size_t sigsBudget = kForPayloadBudgetBytes > fixedBytes ? kForPayloadBudgetBytes - fixedBytes : 1;   // ≥1: 0 = "no budget"

    // L3: field-notes surfacing — parity with the CLI --for lens. loadNoteIndex reads root/.ripwire_notes (a
    // small file); nullptr when EMPTY so the bundle stays byte-identical when there is nothing to surface.
    const notes::NoteIndex        noteIndex = notes::loadNoteIndex( root );
    const notes::NoteIndex* const notesPtr  = noteIndex.empty() ? nullptr : &noteIndex;

    // A2 (survey card, 2026-09-03): sigs render into their OWN buffer (rather than streaming straight into
    // `mem` the way this call used to) so droppedPositive is known BEFORE headerStr is written — headerStr,
    // once flushed to `mem`, cannot be edited retroactively (the same reason the CLI twin's degrade path
    // never gets the attribute). Byte-for-byte the same content this call always produced.
    std::size_t mcpDroppedPositive = 0;
    std::string sigsStr = renderToString( [ & ]( std::FILE* m2 )
    {
        packSignatures( m2, ing, lensRank, forTopN, 0 /* no byte budget in MCP (0 = unlimited) */, true, &fanIn, &impure, redact,
                        nullptr, nullptr, nullptr, nullptr,   // Q3 lens vectors — the MCP verb has no git/clone pass (as before)
                        /*rankAdaptivePayload=*/true,         // B0.3: same rank-adaptive payload rule as the CLI --for lens
                        sigsBudget,                           // H1: global payload budget (trim ladder; payload="capped" marker)
                        notesPtr,                             // L3: field-notes surfacing (inert when null)
                        flRootArg,                            // R-E: root-relative p=, same argument the CLI twin passes
                        /*hasRelevanceFloor=*/true,           // LB-A: shrink past the zero-score tail, never pad
                        &mcpDroppedPositive );                // A2: exact count, see droppedPositiveCount (serialize.h)
    } );
    // A2: same insert-before-"-->" splice as the CLI twin (verbs_for.h) — absent entirely on the (overwhelming)
    // no-drop path, so headerStr's bytes are unchanged there (byte-identical to the pre-A2 output). Bare
    // spelling (no bracket note), same economy and same reasoning as the CLI twin — byte-consistent between
    // the two dialects, the way every other --for header fragment in this function already is.
    if( mcpDroppedPositive > 0 )
    {
        const std::size_t closeAt = headerStr.rfind( " -->" );
        if( closeAt != std::string::npos )
        {
            char nb[ 40 ];
            std::snprintf( nb, sizeof( nb ), " dropped_positive=\"%zu\"", mcpDroppedPositive );
            headerStr.insert( closeAt, nb ); // else: unexpected shape, header left as-is
        }
    }
    std::fwrite( headerStr.data(), 1, headerStr.size(), mem );
    // §P3 × §P4 (parity with the CLI --for): narrow the lego block to the files the budget-trimmed sigs
    // actually kept and re-render (a byte-subset of what the budget already charged for) — reads sigsStr
    // directly now rather than re-slicing it back out of the flushed memstream buffer.
    if( !legoStr.empty() && narrowLegoToRenderedSigs( ing, legoScoped, sigsStr ) )
    {
        legoStr = renderToString( [ & ]( std::FILE* m2 ) { packLego( m2, ing, legoScoped, lensRank, 12, redact, &impure, kNoNode, /*withPaths=*/true, flRootArg ); } );   // R-R: the re-render dropped the root its first render (above) passed
    }
    std::fwrite( sigsStr.data(), 1, sigsStr.size(), mem );
    std::fwrite( legoStr.data(), 1, legoStr.size(), mem );
    std::fwrite( composeStr.data(), 1, composeStr.size(), mem );
    std::fwrite( routeStr.data(), 1, routeStr.size(), mem );   // B6.3
    // DEEP-TAIL d2, MCP twin: the same shared walk + renderer the CLI --for uses (serialize.h), from the
    // same resolved surface — the fixed default budget regime, so the tail rides on top (default row cap)
    // and the ranked head above stays byte-identical to a tail-less bundle.
    {
        std::vector<char> tailEsc;
        const std::string tailStr = renderFileTailXml( computeFileTail( ing, lensRank, lensSurfaceIds, flRootArg ),
                                                       kForFileTailShownCap, tailEsc );
        std::fwrite( tailStr.data(), 1, tailStr.size(), mem );
    }
    std::fprintf( mem, "</ctx>" );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// `lego` verb: the TARGETED interface→impls "Lego" view for ONE named interface/base — its signature,
// method contract (where sound), and EVERY implementor (own-language only), with p= file paths. Mirrors
// the CLI --lego=TYPE exactly (same packLego + resolveFocus + <lego> schema). `type` may be "file:name"
// to disambiguate a same-named type across languages. Returns the <ctx><lego>…</lego></ctx> XML as a
// string, or "" ONLY when `type` does not resolve to any symbol at all (caller reports "not found").
//
// D8 fix: a resolved type with ZERO implementors is NOT the same failure as "not found" — packLego now
// emits that interface's own contract with implementors="0" (the honest "nothing snaps in here yet"
// signal, same as the CLI). Previously this function pre-empted packLego with its own empty-implementors
// check and returned "" for BOTH cases, which is exactly the conflated message the caller downstream had
// to guess at ("type not found or has no implementors"); removing that check lets the two cases produce
// genuinely different, unambiguous outcomes.
inline std::string legoText( const std::string& root, const std::string& type, RedactCounts* redact )
{
    const McpIndex&     ix    = getIndex( root );
    const IngestResult& ing   = ix.ing;
    const NodeId        focus = resolveFocus( ing, type );
    if( focus == kNoNode )
    {
        return {};
    }

    const std::vector<char> impure = computeImpure( ing, ix.g );
    const std::vector<float> flat( ing.symbols.size(), 0.f );

    return captureXml( [ & ]( std::FILE* mem )
    {
        std::fprintf( mem, "<ctx>%s", kLegoLegend );   // H5: the same legend the CLI --lego prints (graphlegend.h)
        packLego( mem, ing, ix.g.implementors, flat, 1, redact, &impure, focus, /*withPaths=*/true,
                  ing.realPaths.empty() ? std::string_view( root ) : std::string_view(),    // R-R: root-relative <iface p=>
                  graphCountFloorAttrXml( ix.g ) );                                           // M15: gauge + marker
        std::fprintf( mem, "</ctx>" );
    } );
}

// `owners` verb: bus-factor analysis — recency-weighted author ownership per file (or per the file
// that defines `symbolName` when non-empty). Reuses gitFileAuthors() from gitmine.h.
// Returns the owners XML text (same shape as --owners CLI output) as a string,
// or "" when git is unavailable / no history (caller converts to an error response).
// §P6.4: CLI/MCP parity — authors=1 files fold into one <uniform/> row here too (gitmine.h's
// countUniformOwnership/ownershipRowsToPrint, shared with main.cpp's --owners), same 75KB-of-identical-
// rows problem applies to an MCP client's context window just as much as a terminal. No `detail` plumbing
// on this path yet (the MCP request shape here carries no such field) — always collapsed, matching the
// CLI's own default.
inline std::string ownersText( const std::string& root, const std::string& symbolName )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;

    // optional symbol→file restriction (mirrors --owners=SYM CLI logic)
    std::uint32_t onlyFileId  = UINT32_MAX;
    std::size_t   symDefCount = 0;      // §B11.3-class: how many definitions the pick below discarded
    std::string   seedSym;              // @-seed rebind: the rebound definition's name, disclosed as sym=
    const NodeId  seedDef     = atSeedDefOr( ing, symbolName );   // the seed's OWN def+file — see its contract
    if( seedDef != kNoNode )
    {
        onlyFileId  = ing.symbols[ seedDef ].fileId;
        symDefCount = 1;                // the seed names ONE place, so exactly one definition is covered
        seedSym     = ing.symbols[ seedDef ].name;
    }
    else if( !symbolName.empty() && symbolName.front() == '@' )
    {
        return {}; // faulted seed — refused upstream; this arm only defends dispatch drift
    }
    else if( !symbolName.empty() )
    {
        const std::vector<NodeId> defs = resolveAllByName( ing, symbolName );
        if( defs.empty() )
        {
            return {}; // symbol not found → caller sends -32602
        }
        // ONE of N definitions — the lowest node id — and the report then covers that definition's file
        // alone under files="1", while callers/uses/impact/mentions on the same name all disclose defs=.
        onlyFileId  = ing.symbols[ defs[0] ].fileId;
        symDefCount = defs.size();
    }

    const std::vector<FileOwnership> ownerships = gitFileAuthors( root, ing, onlyFileId );
    if( ownerships.empty() )
    {
        return {}; // git unavailable or no history → caller sends error
    }

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {};
    }

    const int          cap          = int( ownerships.size() );
    const std::size_t  uniformCount = countUniformOwnership( ownerships, cap );
    const auto          printRows    = ownershipRowsToPrint( ownerships, cap, /*detail=*/false );

    std::vector<char> owEsc;
    // §B6 M12: the files=-DEPTH collision clause, ported from the CLI legend. This element spells `files=`
    // twice with two different meanings — the ROOT's is how many files were ANALYSED, the <uniform/> fold's
    // is how many of them collapsed into that one row — and the CLI defuses it in words while the MCP twin
    // shipped the identical ambiguity undefused. The name is deliberately NOT renamed (both meanings are
    // load-bearing on the CLI side); the disclosure is what travels.
    std::fprintf( mem, "<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). "
                       "bf=1 = one person holds >80%% of weighted commits (bus-factor risk); "
                       "authors=1 files fold into <uniform/> below. "
                       "files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how "
                       "many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. "
                       "With a symbol, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the "
                       "file holding the FIRST of them (lowest node id), so defs= above 1 means the other definitions' files "
                       "were NOT analysed. An @FILE:LINE seed rebinds to the innermost definition enclosing that line "
                       "(sym= names it) and covers exactly that definition's file -->" );
    // §P8: the SAME <owners> element the CLI emits, so it takes the same at=. Stamping only the CLI half
    // would re-create, inside one element name, the two-shapes-one-spelling problem this round removes.
    // §B11.3-class: and the same of=/defs= fold disclosure, for the same reason.
    std::vector<char>  owSymEsc;
    // the @-seed rebind disclosure sits between of= (the seed as typed) and defs=, the same slot the CLI
    // --owners twin uses — §P8: one element name, one attribute order, both surfaces.
    const std::string  owSeedAttr = seedSym.empty() ? std::string{}
                                                    : " sym=\"" + std::string( escapeXml( seedSym, owSymEsc ) ) + "\"";
    const std::string  owSymAttr  = symbolName.empty()
                                  ? std::string{}
                                  : " of=\"" + std::string( escapeXml( symbolName, owSymEsc ) ) + "\"" + owSeedAttr
                                  + " defs=\"" + std::to_string( symDefCount ) + "\"";
    // R-E fix (2026-08-19): the same root-relative p= + root= the CLI --owners now emits, in the same slot
    // (root= before at=, so at= stays LAST — the r26 placement rule). The first R-E landing converted the CLI
    // arm alone and left this one spelling absolute paths, which is the divergence the §P8 note above forbids.
    const bool         owSingleRoot = ing.realPaths.empty();
    const std::string  owRootPrefix = owSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    std::vector<char>  owRootEsc;
    const std::string  owRootAttr   = owSingleRoot ? ( " root=\"" + std::string( rw::escapeXml( root, owRootEsc ) ) + "\"" ) : std::string();
    std::fprintf( mem, "<owners files=\"%zu\"%s%s%s>", ownerships.size(), owSymAttr.c_str(), owRootAttr.c_str(), gitstamp::atAttr( root ).c_str() );
    if( uniformCount > 0 )
    {
        std::fprintf( mem, "<uniform authors=\"1\" bf=\"1\" share=\"1.00\" files=\"%zu\"/>", uniformCount );
    }
    for( std::size_t i : printRows )
    {
        const FileOwnership& ow  = ownerships[i];
        const AuthorScore&   top = ow.authors[0];
        const auto ep = rw::escapeXml( owSingleRoot ? sarif::rootRelativeUri( ing.files[ ow.fileId ], owRootPrefix )
                                                    : std::string_view( ing.files[ ow.fileId ] ), owEsc );
        std::fprintf( mem, "<f p=\"%.*s\" authors=\"%u\" bf=\"%d\"",
                      int( ep.size() ), ep.data(), ow.uniqueAuthors, int( ow.busFactor ) );
        const auto em = rw::escapeXml( top.email, owEsc );
        std::fprintf( mem, " top=\"%.*s\" share=\"%.2f\"/>", int( em.size() ), em.data(), top.share );
    }
    std::fprintf( mem, "</owners>" );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// ─── flagship-reflex verbs (exemplar / impact / uses / path — the write-moment + is-it-safe reflexes) ──────
//
// Each mirrors the identically-named CLI flag, reusing the SAME underlying computation over the warm McpIndex.
// The XML-producing ones (exemplar) return the same <ctx>-wrapped XML the other read verbs (for/lego/owners)
// return; the graph-query ones (impact/uses/path) return the same XML fragment the CLI emits. All are read
// verbs → an unresolved symbol returns "" and the dispatcher maps that to the standard not-found error, never
// a silent empty result. Deterministic: every ranking/sort carries an id tie-break, matching the CLI.

// `exemplar` verb (Q7 write-moment reflex): the repo's BEST-IN-CLASS instance of what the agent is about to
// write, as an imitation target (signature + body). `kindOrTask` is either a kind token
// (fn|method|class|struct|iface|var) or a TASK string whose top lexical match donates its kind. Returns the
// <ctx><exemplar>…</exemplar></ctx> XML with the winner's body (via packBodies), or "" (caller → not-found
// error) when no candidate of the kind exists / no symbol matches the task. `redact` masks credential shapes
// in the emitted body (A3-F3 — same seam contract as the CLI --exemplar); null under --no-redact.
//
// §B6 M2 [BROKEN] — this verb used to be a HAND-ROLLED clone of a selector that stopped existing at A3-F5,
// carrying a source comment asserting an identity ("IDENTICAL … sort") that had been false ever since. The
// clone had no ccx CEILING (invariant 1), no fixture penalty (invariant 2) and no task-to-kind CONFIDENCE
// gate (invariant 3), so `low_confidence=` and `over_ccx_bar=` were structurally unreachable on this surface
// and a nonsense task came back as a confident pick from a bench script where the CLI flags it and falls
// back to fn. Its `candidates=` also counted ALL of the kind (3408) against the CLI's post-ceiling ELIGIBLE
// set (3338) — one attribute name, two populations. It now calls selectExemplar (exemplar.h), the same
// function main.cpp calls, so there is one selector and the divergence class is gone rather than resynced.
inline std::string exemplarText( const std::string& root, const std::string& kindOrTask, RedactCounts* redact = nullptr )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;

    // the selector's two inputs, built exactly as the CLI builds them: tested= from computeQMetrics, fan-in
    // from the in-edge CSR row lengths.
    const QMetrics             qm = computeQMetrics( ing, g );
    const std::size_t          S  = ing.symbols.size();
    std::vector<std::uint32_t> fanIn( S, 0 );
    {
        const auto* ro = g.inEdges.rowOffsets();
        for( std::size_t i = 0; i < S; ++i )
        {
            fanIn[i] = ro[i + 1] - ro[i];
        }
    }

    const ExemplarPick pick = selectExemplar( ing, g, fanIn, qm.tested, kindOrTask );
    if( pick.winner == kNoNode )
    {
        return {}; // no candidate of the kind / task matched nothing → caller reports not-found
    }

    const auto fin = [ & ]( NodeId i ) -> std::uint32_t { return ( i < fanIn.size() )    ? fanIn[i]    : 0u; };
    const auto ts  = [ & ]( NodeId i ) -> std::uint8_t  { return ( i < qm.tested.size() ) ? qm.tested[i] : std::uint8_t( 0 ); };

    // emit the same <ctx><exemplar>…</exemplar></ctx> shape the other read verbs return (G4 valid XML), with
    // the SAME degrade attributes the CLI emits — low_confidence= and over_ccx_bar= are the two facts the
    // clone could never state, so they are the point of the fix, not decoration.
    const Symbol&     wsym = ing.symbols[ pick.winner ];
    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    // G4: collapse '--' runs so the comment can't terminate early. W3FIX M3: same shared scrub as the CLI twin —
    // a '\n' in kindOrTask is a legal XML char escapeXml passes through, and a raw newline outside CDATA is a
    // G4 breach whichever dialect emitted it.
    const std::string reqNote = xmlCommentText( kindOrTask );
    const std::string kindNote = pick.fromTask ? ( " (task -> kind=" + std::string( symTag( pick.targetKind ) )
                                                   + ( pick.lowConfidence ? ", low-confidence: weak match, fell back to fn" : "" ) + ")" )
                                               : std::string();

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {};
    }
    std::fprintf( mem, "<ctx>" );
    // §B6 M13: the rule is exemplar.h's kExemplarSelectionRule, rendered — not restated here in a fourth wording.
    std::fprintf( mem, "<!-- ripwire exemplar for \"%s\"%s: the repo's best-in-class %s to imitate — %s. "
                       "Copy its shape, not its text. -->",
                  ex( reqNote ).c_str(), kindNote.c_str(), symTag( pick.targetKind ), kExemplarSelectionRule );
    // R-E fix (2026-08-19): the CLI twin went root-relative and this one did not, so ONE exemplar came back
    // p="src/infra/fastmath.h:51" on the CLI and the same file spelled as a full absolute path over MCP — the
    // one-answer-two-surfaces contract mcptranchecheck.sh exists to hold. Same single-root condition, same
    // helper, and the same root= disclosure the CLI twin now carries.
    const bool         exSingleRoot = ing.realPaths.empty();
    const std::string  exRootPrefix = exSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const std::string  exRootAttr   = exSingleRoot ? ( " root=\"" + ex( root ) + "\"" ) : std::string();
    std::fprintf( mem, "<exemplar kind=\"%s\" candidates=\"%zu\" n=\"%s\" p=\"%s:%u\" in=\"%u\" ccx=\"%u\"%s%s%s%s>",
                  symTag( pick.targetKind ), pick.candidateCount, ex( wsym.name ).c_str(),
                  ex( exSingleRoot ? sarif::rootRelativeUri( ing.files[ wsym.fileId ], exRootPrefix ) : std::string_view( ing.files[ wsym.fileId ] ) ).c_str(), wsym.line,
                  fin( pick.winner ), wsym.ccx, exRootAttr.c_str(), ts( pick.winner ) ? " tested=\"1\"" : "",
                  pick.lowConfidence ? " low_confidence=\"1\"" : "",
                  pick.overCcxBar    ? " over_ccx_bar=\"1\"" : "" );
    packBodies( mem, ing, { pick.winner }, 0 /* no byte budget in MCP (0 = unlimited) */, g.outOff, g.outTargets, false, redact,
                /*ranges=*/nullptr, /*noteIndex=*/nullptr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                /*withFileContext=*/false, exSingleRoot ? std::string_view( root ) : std::string_view() );
    std::fprintf( mem, "</exemplar></ctx>" );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// `impact` verb (is-it-safe-to-change-X reflex): the transitive blast radius of SYM — every symbol that
// (transitively) reaches SYM via calls, ranked by PageRank (id tie-break). Reuses resolveAllByName +
// transitiveCallers + rankGraph, exactly as the CLI --impact. Returns the <impact>…</impact> XML fragment, or
// "" (caller → not-found error) when SYM has no in-corpus definition.
//
// §B6 M4: `page` is the request's limit/offset (mcpPageArgs, above), applied through the SAME
// pageWindow/effectiveRowCap/pageDisclosure trio the CLI --impact uses — so the 40-row display default is a
// default here too rather than a ceiling, and a paged answer carries the total=/has_more=/next_offset=
// half that lets a caller's loop terminate. Defaulted to {} ⇒ byte-identical to the un-paged answer.
inline std::string impactText( const std::string& root, const std::string& symbol, McpPageArgs page = {} )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;

    // resolveAllByNameQualified — the SAME resolver the CLI --impact uses (byte-identical on a bare
    // name/canonical id), so this twin finally accepts file:name AND the @FILE:LINE line-seed too.
    const std::vector<NodeId> seeds = resolveAllByNameQualified( ing, symbol );
    if( seeds.empty() )
    {
        return {}; // symbol not found → caller reports not-found
    }

    const std::vector<NodeId> reach = transitiveCallers( g, seeds );
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const RankDisclosure      prD{ prIters, prConverged, true };   // W2-F: CLI --impact discloses this; so does its twin
    std::vector<NodeId>       show  = reach;
    std::sort( show.begin(), show.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );

    // A6: the identical isTestSymbol-seeded lens the CLI --impact now runs (graph.h::testSymbolForwardReach)
    // — mcpclidiffcheck compares root-attribute SETS between the two surfaces, so radius_tested=/
    // radius_untested= have to ride here too, over the same un-windowed reach set.
    const std::vector<char> impTestReach   = testSymbolForwardReach( ing, g );
    const std::size_t       radiusTested   = countTestedIn( ing, impTestReach, reach );
    const std::size_t       radiusUntested = reach.size() - radiusTested;

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {};
    }
    // §H4 §3.4: the opener AND the paging clause AND the floor/counting-unit tail now come from the shared
    // constants (src/graphlegend.h + src/pageview.h), so this legend is byte-identical to the CLI --impact
    // one. It was NOT before: this copy carried an abridged paging clause with no limit="0" definition —
    // exactly the §B4 echo-site divergence the shared-constant rule exists to stop.
    // LB-H: the import tier's clause rides here too — the CLI legend and this one are byte-identical by
    // rule, and an attribute the MCP root now carries has to be defined where the caller meets it.
    std::fprintf( mem, "%s%s. %s%s%s%s%s%s-->", kImpactLegendOpen, kPageRaiseCapClause, kImpactImportTierLegend,
                  kTestedRowLegend, kImpactTestedPartitionLegend,   // A6
                  kTestedLensBlindSpotLegend,                       // F-02: rides with the partition, byte-identical to the CLI twin
                  graphCountDisclosure().c_str(), renderDisclosure( prD, DiscloseAs::LegendClause ).c_str() );
    // r27-emitters §P2.1: the listing is capped at 40 by rank. Without shown=/capped= a 40-row answer to
    // "is it safe to change X?" reads as the WHOLE blast radius when it can be 3% of it. Same attributes,
    // same meaning as the CLI --impact — the two surfaces must not diverge on an honesty marker.
    // §B6 M4: the window and the disclosure now come from the shared pageview.h trio, exactly as they do on
    // the CLI arm, instead of a hand-rolled 40-row slice with a hand-rolled shown=/capped= pair.
    const PageWindow  ipw       = pageWindow( show.size(), effectiveRowCap( page.limit, 40 ), page.offset );
    const std::size_t shownRows = ipw.end - ipw.begin;
    char              ipab[ kPageDisclosureCap ];
    // R-E fix (2026-08-19): root-relative p= + root=, exactly as the CLI --impact now emits them. The first
    // R-E landing converted the CLI arm alone, so mcpclidiffcheck's attribute-set lens went red (CLI has
    // root=, MCP does not) and every row answered the same question in a different path dialect.
    const bool         imSingleRoot = ing.realPaths.empty();
    const std::string  imRootPrefix = imSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const std::string  imRootAttr   = imSingleRoot ? ( " root=\"" + ex( root ) + "\"" ) : std::string();
    // LB-H: ONE derivation, shared with the CLI arm (graph.h::impactImportTier) — mcpclidiffcheck compares
    // the two surfaces' attribute sets, and an honesty marker that lands on one of them is the §B4 class.
    const ImportTier imports = impactImportTier( ing, seeds );
    std::fprintf( mem, "<impact of=\"%s\" defs=\"%zu\" reaches=\"%zu\"%s radius_tested=\"%zu\" radius_untested=\"%zu\"%s%s%s%s>",
                  ex( symbol ).c_str(), seeds.size(), reach.size(),
                  imports.xmlAttrs.c_str(), radiusTested, radiusUntested, imRootAttr.c_str(),
                  pageDisclosure( ipab, sizeof( ipab ), shownRows, show.size(), ipw.end, page.limit, page.offset, true ),
                  graphCountFloorAttrXml( g ).c_str(), renderDisclosure( prD, DiscloseAs::XmlAttrs ).c_str() );   // M15: gauge + marker
    for( std::size_t i = ipw.begin; i < ipw.end; ++i )
    { const Symbol& s = ing.symbols[ show[i] ];
      const std::string_view rp = imSingleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], imRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
      // A6: tested="1" only (never a literal 0) — see kTestedRowLegend.
      std::fprintf( mem, "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"%s/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line,
                    isTestedByReach( ing, impTestReach, show[i] ) ? " tested=\"1\"" : "" ); }
    // the import tier's rows, after the symbol rows and under their own tag — a different unit, so a
    // different element (see the CLI arm and kImpactImportTierLegend for why they are never one number).
    emitImportRowsXml( mem, ing, std::span<const std::uint32_t>( imports.files ).first( imports.shown ), imRootPrefix,
                       std::span<const char>( imports.lazy ).first( imports.shown ) );
    std::fprintf( mem, "</impact>" );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// `uses` verb (ABS-3): the use-site index for SYM — the resolvable places its name is REFERENCED (call/read/
// write/import/extends), not just calls, with p="file:line" + the enclosing symbol. Reference-name-based (same
// heuristic level as call edges). external="1" when SYM has no in-corpus definition. Reuses the identical
// reference-scan + deterministic sort as the CLI --uses. Always returns a valid <uses> fragment — a name with
// zero use-sites is a real answer (count="0"), NOT an error, so this verb does not degrade to "".
// V2-1: the MCP surface has no file:name selector — a qualified spelling used to fall
// through as an unresolvable bare name and come back external="1" ("no definition in the indexed tree")
// for a symbol with real in-tree defs: the false-claim class this round exists to kill. ONE helper (both
// dispatch sites — the server's tools/call arm and the batch verb — must refuse identically; the first
// landing guarded only one of them, which is exactly the clone-seam drift pageview.h warns about).
// §B6 M6: the BARE-NAME half of the same class, which the V2-1 guard left one notch open. A name with no
// in-corpus definition AND no use-site at all came back external="1" count="0" — and this verb's own legend
// glosses external= as "stdlib/third-party", so a TYPO received the most confident-sounding answer the verb
// can give, on the surface with no did-you-mean, while the CLI refuses exactly this shape ("matched no
// indexed definition") with a near-miss. The guard mirrors the CLI's predicate exactly: it fires only when
// defs AND sites are both empty, so external="1" WITH real use-sites stays a valid answer — that genuinely
// is a third-party name, and it is the case the attribute exists for.
//
// Returns the refusal message, or "" when the spelling is fine to answer.
// §B11.1 — the V2-1 SENTENCE, hoisted so a verb joins the guard by calling it rather than by someone
// remembering to copy a paragraph. `uses` had it; `owners` and `mentions` take the identical `symbol` field
// through the identical bare-name resolver and answered a qualified spelling with a bare not-found about a
// symbol that plainly exists — the CLI half of that same asymmetry is §B11.1's headline. The MCP policy is
// unchanged and is the one V2-1 decided: qualified selectors are CLI-only HERE, and the refusal says so and
// hands back both retries. Returns "" when the spelling is answerable.
//
// Fires only when the whole spelling resolves to NOTHING and its bare tail resolves to SOMETHING — so an
// ObjC selector, a name that genuinely contains a colon, and a qualified spelling that does resolve are all
// left alone, and a spelling whose tail is not a symbol either falls through to the caller's own not-found.
inline std::string qualifiedSelectorRefusal( const IngestResult& ing, const std::string& symbol, std::string_view cliFlag )
{
    if( !symbol.empty() && symbol.front() == '@' )
    {
        // @FILE:LINE line-seed on a NAME-matching scan verb (owners/mentions — uses intercepts its own
        // @-arm before this helper and rebinds instead). A faulted seed refuses with the shared
        // at-diagnosis; a resolvable one is ANSWERABLE — the 2026-08-30 decision round replaced the
        // first landing's pass-the-name-yourself refusal (which handed the resolved name back as a
        // retry) with the rebind itself: the payload fns (mentionsJson/ownersText) resolve the seed to
        // its ONE enclosing definition and disclose the rebound name, so the one call carries the answer
        // (one-step-smart-defaults), never a re-run hint.
        const AtSeed seed = resolveAtSeed( ing, std::string_view( symbol ).substr( 1 ) );
        if( seed.fault != AtFault::None )
        {
            return mcprefuse::notFound( ing, "symbol", symbol );
        }
        return {};
    }

    const std::size_t lastColon = symbol.rfind( ':' );
    if( lastColon == std::string::npos || lastColon + 1 >= symbol.size() )
    {
        return {};
    }

    const std::string bareName = symbol.substr( lastColon + 1 );
    if( !resolveAllByName( ing, symbol ).empty() )
    {
        return {}; // the whole spelling IS a name
    }
    if( resolveAllByName( ing, bareName ).empty() )
    {
        return {}; // the bare half is not a symbol either
    }

    return "qualified file:name selectors are CLI-only on this verb — pass the bare name '" + bareName
         + "' (the union across its defs), or use the CLI form `ripwire <dir> " + std::string( cliFlag ) + symbol
         + "` for the narrowed answer";
}

inline std::string usesSelectorRefusal( const IngestResult& ing, const std::string& symbol )
{
    if( !symbol.empty() && symbol.front() == '@' )
    {
        // @FILE:LINE: a faulted seed refuses with the shared at-diagnosis (mcprefuse::notFound's @-arm);
        // a resolvable one is answerable — usesText rebinds it to the seed's definition name and serves
        // that name's union answer.
        const AtSeed seed = resolveAtSeed( ing, std::string_view( symbol ).substr( 1 ) );
        if( seed.fault != AtFault::None )
        {
            return mcprefuse::notFound( ing, "symbol", symbol );
        }
        return {};
    }

    const std::size_t lastColon = symbol.rfind( ':' );
    if( lastColon != std::string::npos && lastColon + 1 < symbol.size() )
    {
        return qualifiedSelectorRefusal( ing, symbol, "--uses=" );   // "" when the qualified spelling resolves
    }

    if( !resolveAllByName( ing, symbol ).empty() )
    {
        return {}; // it has a definition — a normal answer
    }
    // member-variable round (card A3): no symbol — a FIELD? One owner answers (usesText); several owners refuse
    // with the Owner.field spellings (the CLI arm's rule, same message, MCP retry syntax); an unserved language
    // refuses by name, as on the CLI.
    if( const std::vector<FieldId> fields = resolveFieldSelector( ing, symbol ); !fields.empty() )
    {
        return memberOwnerRefusal( ing, fields, symbol, "symbol=" );   // "" for one owner — a member answer
    }
    if( const std::string unserved = memberSelectorUnservedRefusal( ing, symbol ); !unserved.empty() )
    {
        return unserved;
    }

    // no definition: refuse ONLY if it also has no use-site (early-exit scan — one match is enough to prove
    // this is a real external name rather than a typo).
    for( const Reference& r : ing.references )
    {
        if( r.calleeName != symbol )
        {
            continue;
        }
        if( r.isCompose || r.isDocLink )
        {
            continue; // type edge / doc mention — not a use-site
        }
        if( r.lang == Lang::Markdown )
        {
            continue; // markdown wikilink — not a code use-site
        }
        return {};                                   // external="1" with real sites: a valid answer, not a typo
    }
    return mcprefuse::notFound( ing, "symbol", symbol,
                                "no indexed definition and no use-site under that spelling — external names with "
                                "real use-sites are answered with external=\"1\", this one has neither" );
}

// The @FILE:LINE rebind the name-matching scan verbs serve through: a resolvable line-seed becomes the
// innermost enclosing definition's NAME (the site scan matches names, so the raw @-spec would silently
// match nothing); anything else — a plain name, or a faulted seed the dispatch guards already refused —
// passes through unchanged. The returned view aliases either the input or a symbol name owned by `ing`.
inline std::string_view atSeedNameOr( const IngestResult& ing, std::string_view sym )
{
    const NodeId seedDef = atSeedDefOr( ing, sym );   // shared with the scan verbs' payload fns
    return seedDef != kNoNode ? std::string_view( ing.symbols[ seedDef ].name ) : sym;
}

inline std::string usesText( const std::string& root, const std::string& symbol, McpPageArgs page = {} )
{
    const McpIndex&        ix   = getIndex( root );
    const IngestResult&    ing  = ix.ing;
    // @FILE:LINE line-seed (the CLI --uses' @-arm, mirrored): serve the seed's definition NAME's union
    // answer; of= keeps echoing the seed as typed, and fault cases are refused upstream (usesSelectorRefusal).
    const std::string_view sym  = atSeedNameOr( ing, symbol );

    const std::vector<NodeId> defs     = resolveAllByName( ing, sym );
    const bool                external = defs.empty();

    // member-variable round (card A3): no symbol but ONE field → the per-site renderer the CLI arm prints (fielduses.h).
    if( const std::vector<FieldId> fields = defs.empty() ? resolveFieldSelector( ing, sym ) : std::vector<FieldId>{}; fields.size() == 1 )
    {
        return renderFieldUses( ing, fields[ 0 ], FieldUsesArgs{ symbol, ing.realPaths.empty(), root, page.limit, page.offset, ix.g } );
    }

    struct UseSite { std::uint32_t fileId; std::uint32_t line; RefRole role; std::string in; };
    std::vector<UseSite> sites;
    for( const Reference& r : ing.references )
    {
        if( r.calleeName != sym )
        {
            continue;
        }
        if( r.isCompose || r.isDocLink )
        {
            continue; // type edge / doc mention — not a use-site
        }
        if( r.lang == Lang::Markdown )
        {
            continue; // markdown wikilink — not a code use-site
        }
        std::string in;
        if( r.fromSymbol != kNoNode && r.fromSymbol < ing.symbols.size() )
        {
            const Symbol& fs = ing.symbols[ r.fromSymbol ];
            // R-R: same root the <u p=…> beside it strips, so in_id= and p= agree on the spelling
            in = canonicalIdForEmit( ing, fs, ing.realPaths.empty() ? std::string_view( root ) : std::string_view() );
        }
        sites.push_back( { r.fileId, r.line, r.role, std::move( in ) } );
    }
    // LB-G (r10 §5): TIER before path and the CLI --uses' own default site cap. mcpclidiffcheck LENS 1
    // pins the two surfaces' root-attribute sets equal, so a cap on one and not the other is a divergence.
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, sites, [ ]( const UseSite& u ) { return u.fileId; } );
    std::sort( sites.begin(), sites.end(), [ & ]( const UseSite& a, const UseSite& b )
               {
        if( const int c = compareTierThenPath( ing, tierOfFile, a.fileId, b.fileId ); c != 0 ) { return c < 0;
}
        if( a.line   != b.line ) {   return a.line < b.line;
}
        if( a.role   != b.role ) {   return std::uint8_t( a.role ) < std::uint8_t( b.role );
}
        return a.in < b.in; } );

    const PageWindow  upw           = pageWindow( sites.size(), effectiveRowCap( page.limit, kUseSiteRowCap ), page.offset );
    const std::size_t upageRows     = upw.end - upw.begin;
    const bool        usDiscloseCap = upageRows < sites.size();
    char              upab[ kPageDisclosureCap ];
    const char* const upage         = pageDisclosure( upab, sizeof( upab ), upageRows, sites.size(), upw.end,
                                                      page.limit, page.offset, usDiscloseCap );

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {};
    }
    // §H4 §3.4 item 2: the opener is the SHARED one (src/graphlegend.h) — this copy and the CLI's were the
    // same false "every use-site of SYM" promise emitted twice, and a fix applied to one of two echo sites
    // is the §B4 failure family. The BODY deliberately stays surface-specific: the CLI legend documents the
    // file:name selector attributes, which this verb has no selector for and does not emit.
    std::fprintf( mem, "%s"
                       "Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. "
                       "external=\"1\" means SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party); "
                       "a qualified file:name spelling whose bare name IS defined refuses instead (the CLI uses verb narrows it). "
                       "%s%s-->%s", kUsesLegendOpen,
                  capLegendClause( computePageDisclosure( upageRows, sites.size(), upw.end,
                                                          page.limit, page.offset, usDiscloseCap ).active ),
                  graphCountDisclosure().c_str(),
                  rootRelPathsLegend( ing.realPaths.empty() ) );   // R-E fix: the CLI --uses legend carries the
                                                                   // identical clause — floormarkcheck (4) pins
                                                                   // the two disclosure tails byte-identical.
    // R-E fix (2026-08-19): root-relative p= + root=, exactly as the CLI --uses now emits them (same finding
    // as impactText above — the first R-E landing converted only the CLI arm).
    const bool         usSingleRoot = ing.realPaths.empty();
    const std::string  usRootPrefix = usSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const std::string  usRootAttr   = usSingleRoot ? ( " root=\"" + ex( root ) + "\"" ) : std::string();
    std::fprintf( mem, "<uses of=\"%s\" defs=\"%zu\" external=\"%d\" count=\"%zu\"%s%s%s>",
                  ex( symbol ).c_str(), defs.size(), external ? 1 : 0, sites.size(), usRootAttr.c_str(), upage, graphCountFloorAttrXml( ix.g ).c_str() );   // of= echoes the selector as TYPED (an @-seed stays an @-seed)
    for( std::size_t siteIndex = upw.begin; siteIndex < upw.end; ++siteIndex )
    {
        const UseSite& u = sites[ siteIndex ];
        const std::string_view up = usSingleRoot ? sarif::rootRelativeUri( ing.files[ u.fileId ], usRootPrefix ) : std::string_view( ing.files[ u.fileId ] );
        std::fprintf( mem, "<u role=\"%s\" p=\"%s:%u\"", refRoleTag( u.role ), ex( up ).c_str(), u.line );
        if( !u.in.empty() )
        {
            std::fprintf( mem, " in_id=\"%s\"", ex( u.in ).c_str() ); // §P8: MCP twin of the CLI --uses rename
        }
        std::fprintf( mem, "/>" );
    }
    std::fprintf( mem, "</uses>" );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// `path` verb: the shortest directed CALL path from `from` to `to` (does A reach B, and how?). Reuses
// resolveFocus + shortestPath, exactly as the CLI --path=A,B. Returns the <path>…</path> XML fragment (with
// reachable="0" hops="0" and no <s> children when B is NOT reachable from A — a valid answer, not an error),
// or "" (caller → not-found error) when EITHER endpoint fails to resolve.
inline std::string pathText( const std::string& root, const std::string& from, const std::string& to )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;

    // r27-emitters §P2.10: resolve EVERY def of each endpoint and run ONE multi-source BFS (shortestPathAny),
    // exactly as the CLI --path now does. Binding `from` to the lowest-NodeId def reported reachable="0" for
    // paths that plainly exist, and the answer never said which def it had picked.
    const std::vector<NodeId> srcDefs = resolveAllByNameQualified( ing, from );
    const std::vector<NodeId> dstDefs = resolveAllByNameQualified( ing, to );
    if( srcDefs.empty() || dstDefs.empty() )
    {
        return {}; // an endpoint not found → caller reports not-found
    }

    const std::vector<NodeId> pth     = shortestPathAny( g, srcDefs, dstDefs );
    const NodeId              srcUsed = pth.empty() ? srcDefs.front() : pth.front();
    const NodeId              dstUsed = pth.empty() ? dstDefs.front() : pth.back();

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — the
    // CLI twin (main.cpp runPath) computes the identical condition so the two dialects cannot diverge.
    const bool         ptSingleRoot = ing.realPaths.empty();
    const std::string  ptRootPrefix = ptSingleRoot ? sarif::rootPrefixOf( root ) : std::string();
    const auto loc = [ & ]( NodeId n ) -> std::string
    { const Symbol& s = ing.symbols[n];
      const std::string_view rp = ptSingleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], ptRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
      return ex( rp ) + ":" + std::to_string( s.line ); };

    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem )
    {
        return {};
    }
    const std::string ptRootAttr = ptSingleRoot ? ( " root=\"" + ex( root ) + "\"" ) : std::string();
    // R-E fix (2026-08-19): the same shared root-relative clause the CLI --path twin now leads with — this
    // verb has no legend of its own either, and the two dialects must not differ on what they explain.
    // H5: the same brief floor legend + marker the CLI --path prints (verbs_navigate.h) — one wording, two transports.
    std::fprintf( mem, "<!-- ripwire path: one DIRECTED call path from= to to= (each <s> a hop); reachable= is 0 and hops= 0 when the "
                       "graph holds none. %s-->%s", kGraphCountFloorBriefLegend, rootRelPathsLegend( ptSingleRoot ) );
    std::fprintf( mem, "<path from=\"%s\" to=\"%s\" from_p=\"%s\" to_p=\"%s\" from_defs=\"%zu\" to_defs=\"%zu\" reachable=\"%d\" hops=\"%zu\"%s%s",
                  ex( from ).c_str(), ex( to ).c_str(), loc( srcUsed ).c_str(), loc( dstUsed ).c_str(),
                  srcDefs.size(), dstDefs.size(),
                  pth.empty() ? 0 : 1, pth.empty() ? std::size_t( 0 ) : pth.size() - 1, ptRootAttr.c_str(),
                  graphCountFloorAttrXml( g ).c_str() );   // M15: gauge + marker
    if( pth.empty() )
    {
        std::fprintf( mem, " hint=\"no directed call path — try the connect verb on %s,%s (undirected: finds a shared caller), or uses/impact for non-call references\"",
                      ex( from ).c_str(), ex( to ).c_str() );
    }
    std::fprintf( mem, ">" );
    for( NodeId n : pth )
    { const Symbol&           s  = ing.symbols[n];
      const std::string_view  rp = ptSingleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], ptRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
      std::fprintf( mem, "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line ); }
    std::fprintf( mem, "</path>" );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// §B6 M8: `path_between`'s not-found refusal, shared by both arms. The old wording — "path endpoint not
// found (from and/or to did not resolve)" — named neither WHICH endpoint failed nor what was typed, on the
// one verb that takes TWO symbols, so the caller had to re-probe both to learn which half to fix. This
// names the failing endpoint(s), echoes each spelling, and offers each one's own near-miss. Returns "" when
// both resolve: a refusal builder that can claim a failure that did not happen is worse than one that
// returns nothing.
inline std::string pathEndpointRefusal( const IngestResult& ing, const std::string& from, const std::string& to )
{
    const bool fromOk = !resolveAllByNameQualified( ing, from ).empty();
    const bool toOk   = !resolveAllByNameQualified( ing, to ).empty();
    if( fromOk && toOk )
    {
        return {};
    }

    // the near-miss clause for ONE endpoint, without re-stating "symbol not found" per side (this refusal
    // already said it once, for both).
    const auto endpoint = [ & ]( std::string_view which, const std::string& spelling ) -> std::string
    {
        std::string part = std::string( which ) + "='" + spelling + "'";
        if( !spelling.empty() && spelling.front() == '@' )
        { // an @FILE:LINE endpoint: the at-diagnosis is the actionable half, a name near-miss is noise
            return part + mcprefuse::atSeedClause( ing, spelling );
        }
        const std::string near = didYouMean( ing, spelling );
        if( !near.empty() && near != spelling )
        {
            part += " (did you mean '" + near + "'?)";
        }
        return part;
    };

    std::string msg = "path endpoint not found: ";
    if( !fromOk )
    {
        msg += endpoint( "from", from );
    }
    if( !fromOk && !toOk )
    {
        msg += ", ";
    }
    if( !toOk )
    {
        msg += endpoint( "to", to );
    }
    msg += " — the other endpoint is fine; fix only the named one";
    if( !fromOk && !toOk )
    {
        msg = msg.substr( 0, msg.rfind( " — " ) ); // both failed: no "the other" to speak of
    }
    return msg;
}

// ─── `connect` — the SHARED <connect> emitter (CLI --connect and the MCP verb write the SAME bytes) ────────
//
// "My task touches these N symbols - how do they RELATE, and which intermediaries matter?" Emits the
// connectSubgraph() result: per connected group the terminals <t>, the
// Steiner intermediaries <s> (with sig= - the intermediary is the thing the agent did NOT name and most
// needs to recognise), and the call edges <e f= t=/> in TRUE caller->callee direction; singleton groups
// land in <unconnected> (honest partitions, never a silent empty). Graph-structured dependency navigation
// beats flat retrieval on exactly this moment (CodeCompass, arXiv 2602.20048); returning the CONNECTING
// subgraph rather than a top-K set is the DeepDiscovery direction (arXiv 2606.22906).
//
// --max-tokens trim order (§4, decided): (1) drop the Steiner sig= bodies -> name-only, (2) drop whole
// MST legs longest-first (ties: lower (termA,termB) pair first - the core's own cap rule) and stamp
// truncated="paths", (3) NEVER drop a terminal or the <unconnected> block - they are the contract.
// Deterministic throughout: every list arrives id-/(from,to)-sorted from the core; the leg-rebuild BFS
// visits a sorted adjacency; trimming drops from a sorted order. Lives here (not serialize.h) because
// serialize.h deliberately never includes graph.h, and main.cpp includes mcp.h - one emitter, two callers
// (the CLI hands stdout, the MCP verb an open_memstream: the path_between pattern without duplication).
namespace connectemit
{
    // rebuild ONE group's node/edge union from its RETAINED legs, by BFS over the group's own (undirected)
    // edge set. Used only when --max-tokens dropped a leg (the fast path emits the core's union verbatim).
    // Deterministic: adjacency sorted ascending by neighbour id; first-discovered prev[] wins.
    struct GroupUnion { std::vector<NodeId> nodes; std::vector<ConnectEdge> edges; };

    // legRetained arrives as a span: the caller's mask is an inline rw::SmallVec, and this seam only reads it.
    inline GroupUnion rebuildFromLegs( const ConnectGroup& grp, std::span<const char> legRetained )
    {
        GroupUnion u;
        u.nodes = grp.terminals;                                   // terminals are ALWAYS present

        // group-local adjacency from the group's true-direction edges; both directions walkable.
        struct Nb { NodeId to; bool viaOut; };                     // viaOut: the stored edge is (node -> to)
        HashMap<NodeId, std::vector<Nb>> adj;
        for( const ConnectEdge& e : grp.edges )
        {
            adj[ e.from ].push_back( { e.to,   true  } );
            adj[ e.to   ].push_back( { e.from, false } );
        }
        for( auto& [ n, v ] : adj )
        {
            std::sort( v.begin(), v.end(), []( const Nb& a, const Nb& b ) noexcept
                       { return a.to != b.to ? a.to < b.to : a.viaOut > b.viaOut; } );
        }

        for( std::size_t li = 0; li < grp.paths.size(); ++li )
        {
            if( !legRetained[li] )
            {
                continue;
            }
            const NodeId srcT = grp.paths[ li ].termA, dstT = grp.paths[ li ].termB;

            // BFS srcT -> dstT over the group subgraph (tiny: <= core node cap), prev + discovery channel.
            HashMap<NodeId, NodeId> prev;
            HashMap<NodeId, char>   viaOut;
            std::vector<NodeId>     q;  q.push_back( srcT );  prev[ srcT ] = srcT;
            bool found = ( srcT == dstT );
            for( std::size_t head = 0; head < q.size() && !found; ++head )
            {
                const auto it = adj.find( q[ head ] );
                if( it == adj.end() )
                {
                    continue;
                }
                for( const Nb& nb : it->second )
                {
                    if( prev.find( nb.to ) != prev.end() )
                    {
                        continue;
                    }
                    prev[ nb.to ] = q[ head ];  viaOut[ nb.to ] = nb.viaOut ? 1 : 0;
                    if( nb.to == dstT ) { found = true; break; }
                    q.push_back( nb.to );
                }
            }
            if( !found )
            {
                continue; // defensive: leg unwalkable in the trimmed union -> skip
            }

            for( NodeId cur = dstT; cur != srcT; cur = prev[ cur ] )
            {
                u.nodes.push_back( cur );
                const NodeId p = prev[ cur ];
                if( viaOut[cur] )
                {
                    u.edges.push_back( { p, cur } ); // p CALLS cur (true direction)
                }
                else
                {
                    u.edges.push_back( { cur, p } ); // cur CALLS p
                }
            }
        }
        const auto edgeLess = []( const ConnectEdge& a, const ConnectEdge& b ) noexcept
        { return a.from != b.from ? a.from < b.from : a.to < b.to; };
        const auto edgeEq   = []( const ConnectEdge& a, const ConnectEdge& b ) noexcept
        { return a.from == b.from && a.to == b.to; };
        std::sort( u.nodes.begin(), u.nodes.end() );
        u.nodes.erase( std::unique( u.nodes.begin(), u.nodes.end() ), u.nodes.end() );
        std::sort( u.edges.begin(), u.edges.end(), edgeLess );
        u.edges.erase( std::unique( u.edges.begin(), u.edges.end(), edgeEq ), u.edges.end() );
        return u;
    }
}   // namespace connectemit

// §P9.3 — the --connect header comment, hoisted OUT of the fprintf so its byte length is a compile-time
// fact instead of a guessed constant. It was guessed at 128 B; it is ~397 B, so the header comment ALONE
// exceeded the est_tokens the verb printed, and the verb under-reported its own document by ~1.7-1.9x.
// serialize.h:524 had already decided the rule for the map family — "the REPORTED est_tokens must cover
// the whole payload the caller receives" — and this is that same rule applied to the one verb that had a
// hand-written estimate of its own. Edit the text and the estimate follows automatically; that coupling is
// the whole point of the constant. (G4: an XML comment may not contain a double hyphen.)
inline constexpr char kConnectHeader[] =
    "<!-- ripwire connect: minimal joining subgraph over N task symbols (metric-closure 2-approx Steiner;"
    " search is undirected so SHARED-CALLER joins are found, every <e f= t=/> keeps its TRUE caller->callee"
    " direction; graph-structured navigation per CodeCompass, arXiv 2602.20048). Call edges are name-based:"
    " dynamic dispatch / callbacks may hide connections. counts_floor=\"1\": every graph-derived count here (nodes=,"
    " edges=, groups=) is a FLOOR, never a total; read a zero as \"none found\", never as \"none exists\"."
    " graph_ambiguous=/graph_unresolved= are the whole graph's resolver gauge (calls split over several defs / calls"
    " whose in-repo defs were all language-filtered), the map header's ambiguous=/unresolved=."
    " defs= on a terminal row = that NAME has N definitions and the lowest-id one was used; qualify with file:name"
    " to pick another. Steiner rows never carry it -->";

// The root element's own bytes: the <connect ...> start-tag PLUS the </connect> close. It is
// self-referential (the start-tag's length depends on the digits of the number it carries), so it is
// BOUNDED rather than measured — a wide start-tag with every counter at five digits and truncated="paths"
// present, plus the 10-byte close. Over-covering slightly is the safe direction: an estimate that
// UNDER-reports is the defect being fixed here, one that over-reports merely trims a little earlier.
inline constexpr std::size_t kConnectRootBytes = 200;   // H5/M15: + counts_floor="1" (17 B) + graph_ambiguous=/graph_unresolved= (≤ 59 B), with margin

// The ONE estimator both the trim-loop fit check and the printed est_tokens go through. Never inline the
// arithmetic at a call site again: two copies of this formula is exactly how the payload-only scope bug
// survived (the printed number and the budget decision must be the same number, by construction).
// `extraBytes` — R-E fix (2026-08-19): the bytes this document carries that the two constants above do not
// bound, i.e. the root= attribute's own length (an absolute crawl root is easily 50+ bytes, and kConnectRootBytes
// is a start-tag bound from before root= existed) plus the shared root-relative legend comment when it is
// emitted. The first R-E landing added root= to the start tag and left the estimator alone, which is exactly
// the UNDER-report kConnectRootBytes' own comment says must never happen. Passed, never re-derived, so the
// trim-loop's fit check and the printed est_tokens still cannot disagree.
inline std::size_t connectEstTokens( std::size_t payloadBytes, std::size_t extraBytes = 0 ) noexcept
{
    const double wholeDocumentBytes = double( payloadBytes ) + double( sizeof( kConnectHeader ) - 1 )
                                    + double( kConnectRootBytes ) + double( extraBytes );
    return std::size_t( wholeDocumentBytes / kBytesPerTokenDefault + 0.5 );
}

inline void packConnect( std::FILE* out, const IngestResult& ing, const Graph& g, const ConnectResult& res,
                         RedactCounts* redact,                  // §B0/W3-N1: REQUIRED — the Steiner-node sig= attrs are emitted text
                         int maxTokens = 0,
                         std::string_view rootArg = {} )   // R-E (2026-08-17): same single-root-only root
                                                           // argument serialize() takes — see its comment.
                                                           // Shared by CLI --connect and the MCP connect verb.
{
    std::vector<char> escBuf;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, escBuf ) ); };
    const std::string rootPrefix = rootArg.empty() ? std::string() : sarif::rootPrefixOf( rootArg );
    const auto         pathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return rootArg.empty() ? std::string_view( ing.files[ fileId ] ) : sarif::rootRelativeUri( ing.files[ fileId ], rootPrefix );
    };
    // R-E fix (2026-08-19): the root= attribute and the shared root-relative legend are part of the document
    // this verb budgets, so they are charged to BOTH the trim-loop fit check and the printed est_tokens. Built
    // once here because connectEstTokens must be called with the same value in both places.
    const std::string  connectRootAttr = rootArg.empty() ? std::string() : ( " root=\"" + ex( rootArg ) + "\"" );
    const std::size_t  connectExtraBytes = connectRootAttr.size() + std::strlen( rootRelPathsLegend( !rootArg.empty() ) );

    // per-file content cache for the Steiner sig= attributes (each needed file read at most once).
    HashMap<std::uint32_t, std::string> contents;
    const auto contentOf = [ & ]( std::uint32_t fid ) -> const std::string&
    {
        const auto it = contents.find( fid );
        if( it != contents.end() )
        {
            return it->second;
        }
        std::string s;
        if( fid < ing.files.size() )
        {
            if( std::FILE* in = std::fopen( diskPath( ing, fid ).c_str(), "rb" ) )
            {
                char b[4096];
                std::size_t n;
                while( ( n = std::fread( b, 1, sizeof( b ), in ) ) > 0 )
                {
                    s.append( b, n );
                }
                std::fclose( in );
            }
        }
        return contents.emplace( fid, std::move( s ) ).first->second;
    };

    // one <t>/<s>/<e> writer set appending to a payload string (built BEFORE the root so est_tokens is honest).
    const auto symAttr = [ & ]( std::string& p, const char* tag, NodeId id )
    {
        const Symbol& s = ing.symbols[ id ];
        p.append( "<" ).append( tag ).append( " n=\"" ).append( ex( s.name ) )
         .append( "\" t=\"" ).append( symTag( s.kind ) )
         .append( "\" p=\"" ).append( ex( pathRel( s.fileId ) ) ).append( ":" ).append( std::to_string( s.line ) ).append( "\"" );
    };

    // §4 trim order: pass 1 full sigs; pass 2 name-only Steiner nodes; then drop legs longest-first
    // (ties: lower (termA,termB) first - the core's own cap ordering) until the estimate fits.
    struct LegRef { std::size_t groupIdx, legIdx; std::uint32_t dist; NodeId a, b; };
    std::vector<LegRef> legOrder;
    for( std::size_t gi = 0; gi < res.groups.size(); ++gi )
    {
        for( std::size_t li = 0; li < res.groups[ gi ].paths.size(); ++li )
        { const ConnectPath& cp = res.groups[ gi ].paths[ li ]; legOrder.push_back( { gi, li, cp.dist, cp.termA, cp.termB } ); }
    }
    std::sort( legOrder.begin(), legOrder.end(), []( const LegRef& x, const LegRef& y ) noexcept
               { return x.dist != y.dist ? x.dist > y.dist : x.a != y.a ? x.a < y.a : x.b < y.b; } );

    bool          withSigs    = true;
    std::size_t   legsDropped = 0;
    std::string   payload;
    std::uint32_t nodeTotal = 0, edgeTotal = 0, connectedGroups = 0;
    for( ;; )
    {
        payload.clear();
        nodeTotal = 0;  edgeTotal = 0;  connectedGroups = 0;

        // retained-leg mask per group for this pass. One byte per leg, so N=8 is free — rw::svector's inline
        // array shares storage with the 8-byte heap pointer it unions with, and <char,8> is 16 B, the same
        // as <char,1> and a third under a std::vector's 24. Rebuilt on every budget-trim pass, so the
        // allocation it stops making is per-group-per-pass, not once.
        std::vector<rw::SmallVec<char, 8>> retained( res.groups.size() );
        for( std::size_t gi = 0; gi < res.groups.size(); ++gi )
        {
            retained[gi].assign( res.groups[gi].paths.size(), 1 );
        }
        for( std::size_t d = 0; d < legsDropped && d < legOrder.size(); ++d )
        {
            retained[legOrder[d].groupIdx][legOrder[d].legIdx] = 0;
        }

        // connected groups first (core order = lowest-terminal-id order), then the <unconnected> singletons.
        for( const ConnectGroup& grp : res.groups )
        {
            if( grp.terminals.size() < 2 )
            {
                continue;
            }
            const std::size_t gi = std::size_t( &grp - res.groups.data() );

            std::vector<NodeId>      steiner = grp.steiner;
            std::vector<ConnectEdge> edges   = grp.edges;
            if( legsDropped > 0 )                                   // a leg went: rebuild this group's union
            {
                const connectemit::GroupUnion u = connectemit::rebuildFromLegs( grp, retained[ gi ] );
                steiner.clear();
                for( NodeId v : u.nodes )
                {
                    if( !std::binary_search( grp.terminals.begin(), grp.terminals.end(), v ) )
                    {
                        steiner.push_back( v );
                    }
                }
                edges = u.edges;
            }
            ++connectedGroups;
            nodeTotal += std::uint32_t( grp.terminals.size() + steiner.size() );
            edgeTotal += std::uint32_t( edges.size() );

            payload.append( "<g terminals=\"" ).append( std::to_string( grp.terminals.size() ) ).append( "\">" );
            for( NodeId t : grp.terminals )
            {
                symAttr( payload, "t", t );
                // M20 (lens 6 F12): a TERMINAL is a caller-typed selector, resolved by resolveFocus's
                // lowest-id pick. --callers/--uses/--impact/--path/--verify all disclose defs= for the same
                // name; the Steiner subgraph did not, so `--connect=size,…` was built from one of six `size`
                // definitions with nothing on the row to say which question was answered. Steiner nodes (the
                // "s" rows) carry no defs= because nobody selected them — the search found them.
                const std::size_t terminalDefs = definitionCountOfName( ing, t );
                if( terminalDefs > 1 ) { payload.append( " defs=\"" ).append( std::to_string( terminalDefs ) ).append( "\"" ); }
                payload.append( "/>" );
            }
            for( NodeId sN : steiner )
            {
                symAttr( payload, "s", sN );
                if( withSigs )
                {
                    const Symbol&      sy  = ing.symbols[ sN ];
                    const std::string& src = contentOf( sy.fileId );
                    if( sy.sigStartByte < sy.sigEndByte && sy.sigEndByte <= src.size() )
                    {
                        payload.append( " sig=\"" ).append( ex( cleanSig( src.data(), sy.sigStartByte, sy.sigEndByte, redact ) ) ).append( "\"" );
                    }
                }
                payload.append( "/>" );
            }
            for( const ConnectEdge& e : edges )
            {
                payload.append( "<e f=\"" ).append( ex( ing.symbols[ e.from ].name ) )
                       .append( "\" t=\"" ).append( ex( ing.symbols[ e.to ].name ) ).append( "\"/>" );
            }
            payload.append( "</g>" );
        }
        for( const ConnectGroup& grp : res.groups )                 // §4: <unconnected> is NEVER trimmed
        {
            if( grp.terminals.size() != 1 )
            {
                continue;
            }
            nodeTotal += 1;
            payload.append( "<unconnected radius=\"" ).append( std::to_string( res.radius ) ).append( "\">" );
            symAttr( payload, "t", grp.terminals[ 0 ] );
            payload.append( "/></unconnected>" );
        }

        // fit check against --max-tokens (0 = no budget) — over the WHOLE document (§P9.3, see kConnectHeader
        // above): the same estimator that produces the printed est_tokens, so the budget the caller sets and
        // the number the caller reads can never disagree.
        const std::size_t est = connectEstTokens( payload.size(), connectExtraBytes );
        if( maxTokens <= 0 || est <= std::size_t( maxTokens ) )
        {
            break;
        }
        if( withSigs )                    { withSigs = false;  continue; }   // trim 1: sigs -> name-only
        if( legsDropped < legOrder.size() ) { ++legsDropped;   continue; }   // trim 2: drop whole legs
        break;                                                               // trim 3 does not exist: terminals + <unconnected> stay
    }

    const bool truncated = res.truncated || legsDropped > 0;
    // §P8 vocabulary: `est_tokens="~191"` was the tool's only NON-NUMERIC token estimate — the `~` made
    // `int(...)` throw in the one field whose whole purpose is arithmetic against a budget, and no other
    // verb apologises for an estimate being an estimate. Dropped.
    const std::size_t estTokens = connectEstTokens( payload.size(), connectExtraBytes );
    std::fprintf( out, "%s%s", kConnectHeader, rootRelPathsLegend( !rootArg.empty() ) );
    std::fprintf( out, "<connect terminals=\"%zu\" nodes=\"%u\" edges=\"%u\" radius=\"%u\" groups=\"%u\" est_tokens=\"%zu\"%s%s%s>",
                  res.terminals.size(), nodeTotal, edgeTotal, res.radius, connectedGroups, estTokens,
                  truncated ? " truncated=\"paths\"" : "", connectRootAttr.c_str(),
                  graphCountFloorAttrXml( g ).c_str() );   // H5/M15: nodes=/edges= are read off the name-based CSR — a floor, with the gauge
    std::fwrite( payload.data(), 1, payload.size(), out );
    std::fprintf( out, "</connect>" );
}

// `connect` verb: resolve the 2..16 symbol specs (resolveFocus - `file:name` disambiguation, exactly the CLI)
// against the warm index, run connectSubgraph, and capture packConnect through a memstream (path_between
// pattern). On failure returns "" with `err` set (unresolved symbol / bad terminal count).
inline std::string connectText( const std::string& root, const std::vector<std::string>& symbolSpecs,
                                std::uint32_t radius, std::string& err, RedactCounts* redact )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;

    if( symbolSpecs.size() < 2 || symbolSpecs.size() > connectcfg::kMaxTerminals )
    { err = "connect needs 2..16 symbols (got " + std::to_string( symbolSpecs.size() ) + ")"; return {}; }

    std::vector<NodeId> terminals;
    for( const std::string& spec : symbolSpecs )
    {
        const NodeId id = resolveFocus( ing, spec );
        if( id == kNoNode ) { err = "symbol not found: " + spec + mcprefuse::atSeedClause( ing, spec ); return {}; }   // the @-clause is "" for a plain name
        terminals.push_back( id );
    }

    const ConnectResult res = connectSubgraph( g, terminals, radius );
    char*       buf = nullptr;
    std::size_t sz  = 0;
    std::FILE*  mem = open_memstream( &buf, &sz );
    if( !mem ) { err = "internal error"; return {}; }
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    packConnect( mem, ing, g, res, redact, /*maxTokens=*/0, ing.realPaths.empty() ? std::string_view( root ) : std::string_view() );
    std::fflush( mem );
    std::fclose( mem );
    std::string out = buf ? std::string( buf, sz ) : std::string{};
    std::free( buf );
    return out;
}

// ─── quality_baseline / quality_delta verbs (the convergence-loop oracle over the warm index) ──────────────
//
// quality_baseline WRITES the `.ripwire_quality_baseline` sidecar (a side-effect verb, like the edit verbs),
// stamping the current HEAD sha. quality_delta is READ-ONLY: it reports ONLY what the working tree made WORSE
// vs the baseline (10 kinds), honoring the exact precedence the CLI --quality-delta uses:
//   (1) an explicit sidecar (from quality_baseline) wins — UNLESS it is STALE (pinned at a different HEAD),
//   (2) else auto-compare vs git HEAD (computeHeadSnapshot), (3) else degrade with a clear message.
// Both reuse quality::computeSnapshot / writeBaseline / selectBaseline / computeHeadSnapshot / gitHeadSha /
// computeDelta — the SAME functions main.cpp's handler calls (no duplicated computation). Step (1) in
// particular is quality::selectBaseline, the single shared seam: R3 (2026-07-29) ended a period where the two
// arms each owned a copy of the staleness test and disagreed about which sidecars were trustworthy.
//
// STATELESS-PER-CALL is fine here: the baseline lives on DISK (the sidecar / git HEAD), not in process memory,
// so a fresh MCP call reconstructs the same comparison the CLI would. Determinism: computeSnapshot + the HEAD
// archive are byte-stable for a fixed tree state, and computeDelta sorts (kind, sym) → the JSON is identical
// run-to-run. NOTE: quality_delta rebuilds ing/graph from disk (NOT the warm McpIndex) so its `rootPath` keys
// match the CLI's cfg.rootPath spelling exactly — the warm index's root may be an absolutized/remote path,
// which would change the baselineCanonId keys and manufacture phantom regressions.
//
// SIDECAR LOCATION — D1 fix: this used to be the one deliberate CLI/MCP divergence (the MCP server's CWD is
// wherever the agent launched it, not `root`, so it root-qualified while the CLI trusted CWD==root). D1
// found that trust was unsound — the CLI is not always invoked from inside its own root either (a wrapper
// script, an orchestrator batching several roots) — so the CLI now root-qualifies too, via the SAME helper
// (quality::rootQualifiedSidecar / quality::baselinePath / quality::acksPath in quality.h; see that header's
// comment for the full rationale). These two are now thin forwarders so every existing call site here keeps
// working unchanged; the canonical implementation lives in quality.h.
inline std::string qualityBaselinePath( const std::string& root ) { return rw::quality::baselinePath( root ); }
inline std::string qualityAcksPath( const std::string& root )     { return rw::quality::acksPath( root ); }

// the applied-vs-HEAD comparison, shared by the JSON emitter. `regs` = the regressions; `baseMarker` = the
// baseline= marker (sidecar / git-HEAD / git-HEAD (stale sidecar ignored)); `ok`=false + `errMsg` when the
// tree is non-git with no sidecar (caller → error, mirroring the CLI exit-1 guidance).
struct QualityDeltaOutcome
{
    bool                              ok = false;
    std::string                       errMsg;        // on degrade (non-git, no sidecar)
    std::string                       baseMarker;    // "sidecar" | "git-HEAD" | "git-HEAD (stale sidecar …)" — see §B6 M10 below
    std::vector<rw::quality::Regression> regs;
    std::size_t                       ackedCount = 0;// findings suppressed by the .ripwire_quality_acks ratchet (honest suppression)
    std::vector<rw::quality::StaleAck> staleAcks;     // L2 — acks whose target no longer applies to this working tree (see quality::computeStaleAcks)
    // R1 IDENTITY — the same disclosure the CLI root carries, so an MCP-only agent is told what an ack's
    // survival across a rename rested on. It has no CLI to re-ask from; a fact that exists on one surface and
    // not the other is the §B6 M5 divergence this file has paid for once already.
    bool                              renamesAvailable = false;
    std::size_t                       renamesRecorded  = 0;
    std::size_t                       ackedByRename    = 0;
    std::size_t                       ackedByContent   = 0;
    std::size_t                       schemeRekeyed    = 0;   // the git-INDEPENDENT key-scheme replay
    std::size_t                       schemeAmbiguous  = 0;
    std::size_t                       registerMacroExcluded = 0;   // P2.2: the CLI's disclosed dead-code exemption count — see quality.h
};

// §B6 M10 — a CORRUPT sidecar used to read as "no sidecar". readBaseline reports a file that yields no header,
// no `head` stamp and no record line as ABSENT (correct — a broken pin is not a floor), and selectBaseline then
// hands back the bare "git-HEAD" marker, which is the SAME answer a tree with NO sidecar at all gets. The only
// disclosure was a server-side DEGRADED_PATH_ALERT on stderr, which no MCP client surfaces: the agent saw a
// clean baseline:"git-HEAD" and could not know its pinned floor had silently stopped being read.
//
// Absent-vs-present is a fact this arm can establish on the path it already knows: a bare "git-HEAD" means the
// sidecar was neither honored nor stale, so a file sitting at `sidecar` can only be one readBaseline rejected.
// Reported in the MARKER, where the other "not the floor you think" state ("stale sidecar ignored") is already
// reported, and read-only exactly like this arm's stale policy — the file is left on disk. Deliberately NOT a
// quality.h change: the marker vocabulary there is shared with the CLI arm, and this states an MCP-arm fact
// without moving the shared table.
//
// It is a named step rather than a block inside computeQualityDelta so that "which marker does this arm
// report" has ONE answer with ONE reason, and adding a state later is an arm here instead of another `if`
// buried in the middle of an ingest-and-compare function.
inline const char* mcpBaselineMarker( const rw::quality::BaselineSelection& selection, const std::string& sidecarPath )
{
    if( selection.source != rw::quality::BaselineSource::Absent )
    {
        return selection.marker;
    }

    std::error_code sidecarEc;
    if( std::filesystem::exists( std::filesystem::path( sidecarPath ), sidecarEc ) && !sidecarEc )
    {
        return "git-HEAD (unreadable sidecar ignored)";   // present on disk, rejected by readBaseline
    }
    return selection.marker;                              // genuinely absent — "git-HEAD"
}

inline QualityDeltaOutcome computeQualityDelta( const std::string& root )
{
    QualityDeltaOutcome oc;

    // rebuild ing/graph from disk with root exactly as invoked → baseline keys match the CLI key-for-key.
    // Phase-M: serialize this working-tree ingest against a concurrent qsnap-prefetch worker (ingest() writes
    // single-writer process-global caches). The computeHeadSnapshot call below locks
    // the SAME mutex internally, so keep this guard SCOPED to the ingest only (no re-entrant lock → no deadlock).
    IngestResult ing;
    {
        std::lock_guard<std::mutex> ingestLk( rw::quality::headSnapshotIngestMutex() );
        ing = ingest( root.c_str(), {}, {} );
    }
    const Graph  g   = buildGraph( ing, nullptr );

    const std::string sidecar = qualityBaselinePath( root );   // root-qualified (see SIDECAR LOCATION note)

    // STALENESS lives in quality::selectBaseline — the ONE seam both arms share (R3 owner ruling, 2026-07-29).
    // A sidecar pinned at a DIFFERENT HEAD than the current one is STALE (abandoned/parallel session, or
    // written before a commit): trust it and quality_delta reports a wall of false regressions. This arm's own
    // POLICY is `removeStaleFile=false` — quality_delta is READ-ONLY, so the stale file is left on disk and
    // merely ignored ("git-HEAD (stale sidecar ignored)"), where the CLI passes true and self-heals it away.
    // The strict-equality test itself used to be MCP-only; the CLI carried a reachable-ancestor carve-out that
    // made it honor sidecars this arm dropped, which is the divergence R3 revoked.
    rw::quality::BaselineSelection baseSel = rw::quality::selectBaseline( root, sidecar, /*removeStaleFile=*/false );
    if( !baseSel.isSidecarHonored() )
    {
        auto [ headSnap, headOk ] = rw::quality::computeHeadSnapshot( root );
        if( !headOk )
        {
            oc.ok = false;
            // w1 sibling sweep: this arm passes removeStaleFile=false, so a stale sidecar ALWAYS survives here
            // (baseSel.isStaleFileOnDisk() is true whenever isSidecarStale() is) — "delete it" is therefore
            // always the true instruction and the wording needs no removed-vs-ignored split. The CLI twin,
            // which unlinks, does branch on isStaleFileOnDisk().
            oc.errMsg = baseSel.isSidecarStale()
                ? std::string( rw::quality::kBaselineFile ) + " is STALE (pinned at a different HEAD) and there is no current HEAD tree to fall back to — delete it or re-run the quality_baseline verb"
                : std::string( "no " ) + rw::quality::kBaselineFile + " and no git HEAD to auto-compare against — run the quality_baseline verb BEFORE the change you want to measure";
            return oc;
        }
        baseSel.snapshot = std::move( headSnap );
    }

    // R1 IDENTITY: the SAME healing pre-pass the CLI runs, through the one entry point, and BEFORE
    // computeDelta reads the baseline. §B6 M5 / R3 is the standing lesson — the moment this arm carries its
    // own copy of a rule the two surfaces answer one question differently in the same second. This verb is
    // read-only, so it never WRITES content ids (wantContentIds=false); it still uses the ones a row carries.
    auto       acks = rw::quality::readAckRecords( qualityAcksPath( root ) );
    const auto heal = rw::quality::healIdentity( baseSel.snapshot, acks, ing, g, root, root, /*wantContentIds=*/false );

    oc.regs       = rw::quality::computeDelta( ing, g, baseSel.snapshot, root, {}, rw::kDefaultMaxFileBytes, &oc.registerMacroExcluded );

    // signal-to-noise round: honor the per-finding ack ratchet exactly like the CLI — the acks sidecar is
    // root-qualified (same SIDECAR LOCATION discipline as the baseline), suppression is reported via `acked`.
    rw::quality::countAckRescues( oc.regs, acks, heal.ackRemap, oc.ackedByRename, oc.ackedByContent );
    oc.renamesAvailable = heal.renames.available;
    oc.renamesRecorded  = heal.renames.pairsRecorded;
    oc.schemeRekeyed    = heal.ackRemap.schemeRekeyed;
    oc.schemeAmbiguous  = heal.schemeAmbiguousAcks;
    oc.ackedCount   = rw::quality::applyAckRatchet( oc.regs, acks );

    // L2 — same stale-ack disclosure the CLI's --quality-delta reports (see quality.h's computeStaleAcks):
    // checked against THIS working tree, never the baseline above, so it costs one more computeSnapshot pass
    // over `ing`/`g` already built here; skipped when the ledger is empty (test/mcpclidiffcheck.sh's LENS2
    // pins the two surfaces to the same JSON key set).
    if( !acks.empty() )
    {
        oc.staleAcks = rw::quality::computeStaleAcks( acks, rw::quality::computeSnapshot( ing, g, root ) );
        rw::quality::stampStaleAckIdentity( oc.staleAcks, ing, root );   // M21(a): the CLI twin's sym=/p=
    }

    // R3: the marker spelling table lives in selectBaseline, so CLI and MCP name the same state the same way;
    // §B6 M10: plus this arm's own unreadable-sidecar state (mcpBaselineMarker, above).
    oc.baseMarker = mcpBaselineMarker( baseSel, sidecar );
    oc.ok         = true;
    return oc;
}

// quality_delta → JSON. "" ONLY on the non-git/no-sidecar degrade (caller reports the error message).
//
// §B6 M5 [MISLEADING] — this payload and the CLI's `--quality-delta --json` were two JSON documents about
// one computation that disagreed on the two things a consumer reads FIRST:
//   • `regressions` was an ARRAY here and an INTEGER on the CLI (whose array is `r`), so a script written
//     against one surface reads the other's count as a list and its list as a count.
//   • `minor` and `at` were absent — `at` being the BASELINE SHA, dropped on the one verb whose entire
//     meaning is "worse than a baseline", which left an MCP answer unattributable to the tree it judged.
// The keys now mirror the CLI's exactly, header AND rows (p= locator, per-row gating, the churn/surface
// facet names, displaySym's root-relative spelling, and the CLI's own was/now omission rule for the
// zero-magnitude kinds). `regressions_count` is gone rather than kept as an alias: two names for one number
// is how the next consumer picks the wrong one. Gate: test/mcpclidiffcheck.sh diffs the two key sets.
inline std::string qualityDeltaJson( const std::string& root, std::string& errOut )
{
    const QualityDeltaOutcome oc = computeQualityDelta( root );
    if( !oc.ok ) { errOut = oc.errMsg; return {}; }

    // r26 ORIGIN SPLIT — the same three counts main.cpp derives, so both surfaces encode one contract.
    std::size_t minorCount = 0, newSymbolCount = 0, gatingCount = 0;
    for( const rw::quality::Regression& r : oc.regs )
    {
        if( r.isMinor )
        {
            ++minorCount;
        }
        if( r.isNewSymbol )
        {
            ++newSymbolCount;
        }
        else if( !r.isMinor )
        {
            ++gatingCount;
        }
    }

    // the baseline anchor: "at":null on a non-git root (never a fake sha) — the CLI's own convention.
    const std::string atVal  = gitstamp::stampAt( root );
    const std::string atJson = atVal.empty() ? std::string( "null" ) : ( "\"" + mcpdetail::jsonEscape( atVal ) + "\"" );

    std::string out = "{\"baseline\":\"" + mcpdetail::jsonEscape( oc.baseMarker )
                    + "\",\"regressions\":" + std::to_string( oc.regs.size() )
                    + ",\"minor\":" + std::to_string( minorCount )
                    + ",\"acked\":" + std::to_string( oc.ackedCount )
                    + ",\"stale\":" + std::to_string( oc.staleAcks.size() )
                    + ",\"preexisting-worse\":" + std::to_string( oc.regs.size() - newSymbolCount )
                    + ",\"new-symbol\":" + std::to_string( newSymbolCount )
                    + ",\"gating\":" + std::to_string( gatingCount )
                    // P2.2 — the CLI's disclosed dead-code exemption count, ALWAYS present (never omitted at
                    // zero, unlike the identity fields just below): mcpclidiffcheck.sh's JSON-key-set lens
                    // diffs this verb against `--quality-delta --json`, and the CLI never omits it either.
                    + ",\"register-macro-excluded\":" + std::to_string( oc.registerMacroExcluded )
                    // R1 IDENTITY — the CLI root's identity disclosure, spelled in JSON. Present only when
                    // git could be read at all, exactly like the CLI arm (absent ≠ zero — see the legend).
                    + ( oc.schemeRekeyed ? ",\"acks_rekeyed_by_scheme\":" + std::to_string( oc.schemeRekeyed ) : std::string{} )
                    + ( oc.schemeAmbiguous ? ",\"scheme_ambiguous\":" + std::to_string( oc.schemeAmbiguous ) : std::string{} )
                    + ( oc.renamesAvailable ? ( ",\"renames\":" + std::to_string( oc.renamesRecorded )
                                              + ",\"acked_by_rename\":" + std::to_string( oc.ackedByRename )
                                              + ",\"acked_by_content\":" + std::to_string( oc.ackedByContent ) )
                                            : std::string{} )
                    + ",\"at\":" + atJson + ",\"r\":[";
    bool first = true;
    for( const rw::quality::Regression& r : oc.regs )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        // duplication carries a member LIST + token count; the zero-magnitude kinds (dead-code, and
        // api-surface when was==now) are sym-only; every other kind carries was/now — the CLI's exact split.
        out += "{\"kind\":\"" + mcpdetail::jsonEscape( r.kind ) + "\"";
        if( r.kind == "duplication" )
        {
            out += ",\"members\":\"" + mcpdetail::jsonEscape( rw::quality::displaySym( r.sym, root ) )
                 + "\",\"tokens\":" + std::to_string( r.now );
        }
        else
        {
            out += ",\"sym\":\"" + mcpdetail::jsonEscape( rw::quality::displaySym( r.sym, root ) ) + "\"";
            if( !( r.kind == "dead-code" ) && !( r.kind == "api-surface" && r.was == r.now ) )
            {
                out += ",\"was\":" + std::to_string( r.was ) + ",\"now\":" + std::to_string( r.now );
            }
        }
        if( !r.path.empty() )
        {
            out += ",\"p\":\"" + mcpdetail::jsonEscape( r.path ) + ":" + std::to_string( r.line ) + "\""; // P2.5 locator
        }
        if( !r.isNewSymbol && !r.isMinor )
        {
            out += ",\"gating\":true"; // the exit predicate, per row
        }
        if( r.isMinor )
        {
            out += ",\"sev\":\"minor\"";
        }
        if( !r.facet.empty() )
        {
            const char* facetName = rw::quality::facetAttrName( r.kind );   // ONE kind→name table (quality.h)
            if( facetName )
            {
                out += ",\"" + std::string( facetName ) + "\":\"" + mcpdetail::jsonEscape( r.facet ) + "\"";
            }
        }
        if( r.isNewSymbol )
        {
            out += ",\"origin\":\"new-symbol\""; // absent = preexisting-worse (mirrors the XML)
        }
        out += "}";
    }
    out += "],";     // L2 — "sa":[...], same taxonomy the CLI's <sa kind= key= why=/> rows carry (shared builder, quality::staleAcksJsonArray)
    out += rw::quality::staleAcksJsonArray( oc.staleAcks );
    out += "}";
    return out;
}

// quality_baseline → writes `.ripwire_quality_baseline` (side-effect verb) stamped with HEAD, returning a JSON
// summary of what it wrote. Reuses quality::computeSnapshot + writeBaseline + gitHeadSha — the exact CLI path.
// The sidecar is written in `root` (same as the CLI, which uses cfg.rootPath). Returns "" + fills errOut when
// the write fails (unwritable dir). Rebuilds ing/graph from disk so the snapshot keys match the CLI.
inline std::string qualityBaselineJson( const std::string& root, std::string& errOut )
{
    IngestResult ing;                                          // Phase-M: serialize the ingest vs the prefetch worker (§2b)
    {
        std::lock_guard<std::mutex> ingestLk( rw::quality::headSnapshotIngestMutex() );
        ing = ingest( root.c_str(), {}, {} );
    }
    const Graph  g   = buildGraph( ing, nullptr );

    const std::string sidecar = qualityBaselinePath( root );   // root-qualified (see SIDECAR LOCATION note)
    const std::string headSha = rw::quality::gitHeadSha( root );
    const bool wrote = rw::quality::writeBaseline( rw::quality::computeSnapshot( ing, g, root ),
                                                    sidecar, headSha );
    if( !wrote )
    {
        errOut = std::string( "could not write " ) + sidecar + " (unwritable directory?)";
        return {};
    }
    return std::string( "{\"wrote\":\"" ) + mcpdetail::jsonEscape( sidecar )
         + "\",\"symbols\":" + std::to_string( ing.symbols.size() )
         + ",\"head_sha\":\"" + mcpdetail::jsonEscape( headSha.empty() ? std::string( "(none — not a git repo)" ) : headSha )
         + "\",\"note\":\"baseline pinned; re-run the quality_delta verb after each edit to see only what got worse\"}";
}

// ─── L4: the B11-verb-parity MCP twins — `explore`/`pack_task`,
// `from_trace`, `edit_check`. Each is a thin front door onto the SAME shared assembler its CLI sibling calls
// (packtask.h / tracelocus.h / editcheck.h) — no forked logic, no drifting XML shape between the two
// surfaces. `merge_scout` and `note-add`/`notes` stay CLI-only (write verbs / multi-ref UX; see
// skills/ripwire-mcp).

// `explore`/`pack_task` verb: the MCP twin of --pack-task — ONE call assembling the routed ranking + full
// bodies + 1-hop callers + field notes + tests_to_run under ONE deterministic byte budget. Computes the lens
// ranking with the SAME primitives forTaskText (the `for` verb, above) uses — chooseForRanker / lexicalScores
// / applyMentionBoost / applyCoChangeBoost — then hands the populated LensRanking to packTaskBundleText()
// (packtask.h), the SAME assembler --pack-task's CLI handler (main.cpp runPackTask) calls. `budgetTokens` 0
// ⇒ the shared default (6000). No --anchor/--no-route equivalent over MCP (routing is always-on here, as it
// is by default on the CLI; --anchor is a CLI-only RIPWIRE_DEV-gated experiment).
//
// `partitionCount` is the CLI's --partition=N over MCP — an ARGUMENT on this verb, not a
// verb of its own, because it changes what `explore` returns (one bundle vs core + N slices) without changing
// what it is FOR; a separate verb would duplicate the whole task/budget contract for one integer. 0 (or any
// value outside 2..16, which is silently clamped OFF rather than erroring an otherwise valid explore call)
// ⇒ the plain single-bundle form, byte-identical to before.
inline std::string packTaskText( const std::string& root, const std::string& task, std::size_t budgetTokens,
                                 RedactCounts* redact = nullptr, std::uint32_t partitionCount = 0 )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;

    LensRanking       lr;
    const RouteChoice rc = chooseForRanker( ing, task );
    std::vector<char> ifaceExact( ing.symbols.size(), 0 );
    for( std::size_t i = 0; i < ix.g.implementors.size() && i < ifaceExact.size(); ++i )
    {
        if( !ix.g.implementors[i].empty() )
        {
            ifaceExact[i] = 1;
        }
    }
    // Query SHAPE + §P4 tier de-prioritization — same classifier, same multiplier, same order (before the
    // mention anchor) as CLI --pack-task.
    const queryshape::Verdict shape   = queryshape::classify( task );
    const std::vector<float>  tierMul = rankTierSymbolMultipliersShaped( ing, shape.fires() );
    lr.rank      = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExactRanked( ing, task, &tierMul )
                                                       : lexicalScoresTiered( ing, g.outOff, g.outTargets, task, 0, &ifaceExact, &tierMul );
    lr.routeNote = " [routed: " + rc.reason + shapeDemotionNote( shape ) + "]";

    if( !std::getenv( "RIPWIRE_NO_MENTION" ) )
    {
        MentionBoostInfo mentionInfo;
        if( applyMentionBoost( ing, task, lr.rank, &mentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [mention anchor: %u file%s + %u symbols named in the task, score lifted to within 5%% of the top score]",
                           mentionInfo.fileCount, mentionInfo.fileCount == 1 ? "" : "s", mentionInfo.symbolCount );
            lr.mentionNote = nb;
        }
    }
    if( std::getenv( "RIPWIRE_COCHANGE" ) && hasEnclosingGitRepo( root ) )
    {
        const auto  coSets = gitRecentCommitFileSets( root, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit );
        CoBoostInfo boostInfo;
        if( !coSets.empty() && applyCoChangeBoost( ing, coSets, lr.rank, &boostInfo ) )
        {
            char nb[ 200 ];
            std::snprintf( nb, sizeof( nb ), " [cochange boost: promoted %u symbols in %u files that historically change with the top seeds (last %u commits)]",
                           boostInfo.boostedSymbolCount, boostInfo.boostedFileCount, kCoBoostCommitWindow );
            lr.boostNote = nb;
        }
    }
    if( !std::getenv( "RIPWIRE_NO_DOC_MENTION" ) )
    {
        DocMentionBoostInfo docMentionInfo;
        if( applyDocMentionBoost( g, lr.rank, &docMentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [doc mentions: %u doc%s discussing %u top-ranked symbol%s surfaced]",
                           docMentionInfo.docCount, docMentionInfo.docCount == 1 ? "" : "s",
                           docMentionInfo.anchorCount, docMentionInfo.anchorCount == 1 ? "" : "s" );
            lr.docMentionNote = nb;
        }
    }

    const std::vector<char>    impure = computeImpure( ing, g );
    std::vector<std::uint32_t> fanIn( ing.symbols.size(), 0 );
    {
        const auto* ro = g.inEdges.rowOffsets();
        for( std::size_t i = 0; i < ing.symbols.size(); ++i )
        {
            fanIn[i] = ro[i + 1] - ro[i];
        }
    }

    const notes::NoteIndex        noteIndex = notes::loadNoteIndex( root );
    const notes::NoteIndex* const notesPtr  = noteIndex.empty() ? nullptr : &noteIndex;

    PackTaskInputs in;
    in.budgetTokens = budgetTokens;
    in.fanIn        = &fanIn;
    in.impure       = &impure;
    in.redact       = redact;
    in.notes        = notesPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — the
    // CLI twin (main.cpp runPackTask) sets the identical field so the two dialects cannot diverge.
    in.rootArg = ing.realPaths.empty() ? std::string_view( root ) : std::string_view();
    if( partitionCount >= packpartition::kMinPartitions && partitionCount <= packpartition::kMaxPartitions )
    {
        return packpartition::packTaskPartitionText( ing, g, task, lr, in, partitionCount );
    }
    return packTaskBundleText( ing, g, task, lr, in );
}

// `from_trace` verb: the MCP twin of --from-trace — maps a pasted stack trace / sanitizer report / compiler
// error onto indexed symbols, ranked INNERMOST-first, via fromTraceBundleText() (tracelocus.h) — the SAME
// assembler the CLI --from-trace handler calls. `trace` is the raw trace TEXT (no stdin/file reading over
// MCP — the caller pastes it as a request argument, unlike the CLI's FILE/'-' arg). "" ⇒ zero parseable
// frames (caller → error, mirroring the CLI's loud refusal).
inline std::string fromTraceText( const std::string& root, const std::string& trace, std::size_t budgetTokens, RedactCounts* redact = nullptr )
{
    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;
    const Graph&        g   = ix.g;

    const std::vector<char>    impure = computeImpure( ing, g );
    std::vector<std::uint32_t> fanIn( ing.symbols.size(), 0 );
    {
        const auto* ro = g.inEdges.rowOffsets();
        for( std::size_t i = 0; i < ing.symbols.size(); ++i )
        {
            fanIn[i] = ro[i + 1] - ro[i];
        }
    }
    const notes::NoteIndex        noteIndex = notes::loadNoteIndex( root );
    const notes::NoteIndex* const notesPtr  = noteIndex.empty() ? nullptr : &noteIndex;

    FromTraceInputs in;
    in.bundleBudgetBytes = budgetTokens > 0
        ? std::size_t( double( budgetTokens ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : rw::kForPayloadBudgetBytes;
    in.fanIn  = &fanIn;
    in.impure = &impure;
    in.redact = redact;
    in.notes  = notesPtr;
    in.rootArg = ing.realPaths.empty() ? std::string_view( root ) : std::string_view();   // R-R

    const FromTraceResult res = fromTraceBundleText( ing, g, trace, "mcp trace input", in );
    return res.ok ? res.xml : std::string();
}

// `edit_check` verb: the MCP twin of --edit-check=SYM — "did MY edit change a contract someone depends on",
// via editCheckBundleText() (editcheck.h), the SAME contract-comparison core the CLI --edit-check handler
// calls. Rebuilds ing/graph FRESH from disk (NOT the warm McpIndex) so its root-relative baselineCanonId keys
// match the CLI's exactly — same precedent as computeQualityDelta() above (a warm index's root may be
// absolutized/remote-spelled, which would manufacture phantom contract-changes).
//
// TWO fields, and exactly one of them is ever populated: an empty payload ALWAYS carries the reason in
// `refusal`, so the dispatcher stays a single "payload or refusal" branch and can never invent a message the
// verb did not choose.
//
// §A6a parity: an AMBIGUOUS symbol is REFUSED here for the identical reason the CLI refuses it — a contract is
// per definition site, so answering about one of N silently is exactly the failure this verb exists to
// prevent. Both surfaces word it with editCheckAmbiguousMessage(), so they cannot drift apart.
struct EditCheckReply { std::string payload; std::string refusal; };

//
// card A1 — `new_body` turns this into the PRE-APPLY preview: the same question about bytes that have not
// been written. Nothing writes; the field is optional and the verb stays readOnlyHint:true. The CLI form is
// --edit-check=SYM --edit-payload=FILE --dry-run, and both surfaces route through editpreview::run, so the
// two cannot answer differently.
inline EditCheckReply editCheckText( const std::string& root, const std::string& symbol, const std::string& newBody = {} )
{
    IngestResult ing;   // Phase-M: serialize the ingest vs the qsnap-prefetch worker (§2b), same as computeQualityDelta
    {
        std::lock_guard<std::mutex> ingestLk( rw::quality::headSnapshotIngestMutex() );
        ing = ingest( root.c_str(), {}, {} );
    }
    const Graph g = buildGraph( ing, nullptr );

    const std::vector<NodeId> matches = resolveAllByNameQualified( ing, symbol );
    // verifier N5: this was the last MCP not-found still speaking the pre-M8 dialect — four words, no echo of
    // the spelling, no near-miss — on the one verb an agent reaches for right after a rename, where a typo
    // and a genuinely absent symbol are the two likeliest causes and the message distinguished neither.
    if( matches.empty() )
    {
        return EditCheckReply{ {}, mcprefuse::notFound( ing, "symbol", symbol,
                                                        mcprefuse::notFoundHintFor( "edit_check", "symbol" ) ) };
    }

    const std::vector<EditCheckGroup> groups = editCheckGroups( ing, g, matches );
    if( groups.size() > 1 )
    {
        return EditCheckReply { {}, editCheckAmbiguousMessage( symbol, groups, "symbol=", matches.size() ) };
    }

    if( !newBody.empty() )
    {   // the two payload refusals a STRING argument can still trip — the file-side ones (unreadable, over the
        // size ceiling) belong to the CLI's own reader. A payload with no definition in it lands on
        // editpreview::run's "does not define SYM", which is the honest sentence for a blank one too.
        if( looksBinary( newBody ) )
        {
            return EditCheckReply{ {}, "new_body " + std::string( mcpedit::kBinaryPayloadRefusal ) };
        }
        const rw::editpreview::Outcome preview =
            rw::editpreview::run( ing, g, root, kDefaultMaxFileBytes, {}, true, symbol, groups[0].lowestNode, newBody, nullptr );
        return preview.ok ? EditCheckReply{ preview.xml, {} } : EditCheckReply{ {}, preview.message };
    }

    return EditCheckReply{ editCheckBundleText( ing, g, root, kDefaultMaxFileBytes, {}, groups[0].lowestNode ), {} };
}

// ─── `slice` verb (lane/tc-sliceat): the ARISE def-use slice over MCP, mirroring the CLI --slice ────────
//
// One contract, two surfaces: SYM lists the sliceable locals; SYM+var (or the SYM:VAR spelling — the two
// answer byte-identically) serves the per-line def-use rows; flow=back|fwd|both adds the rung-2 transitive
// data-flow slice with depth bounding it (1..32, default 8); @FILE:LINE seeds by location, pre-picking the
// variable when the seed line names exactly one sliceable local (disclosed — seed=/var_from=/seed_vars=,
// the CLI's own vocabulary, because sliceBundleText is the ONE emitter both surfaces call). Refusals mirror
// the CLI refusal-for-refusal: not-found (echo + near-miss + at-diagnosis), ambiguity (spellings listed,
// never a silent pick), unserved language (the served list named), unknown var (locals listed), flow
// misuse. Single-root by table (kMcpSingleRootVerbs): the slice re-parses the definition's on-disk file,
// which a merged multi-root graph cannot address unambiguously.
struct SliceReply { std::string payload; std::string refusal; };

inline SliceReply sliceText( const std::string& root, const std::string& symbol, const std::string& var,
                             const std::string& flow, int depth, RedactCounts* redact )
{
    // argument-shape refusals first — they need no index
    if( !flow.empty() && flow != "back" && flow != "fwd" && flow != "both" )
    {
        return SliceReply{ {}, "flow '" + mcprefuse::cappedEcho( flow ) + "' is not a direction (supported: back|fwd|both)" };
    }
    if( depth > 0 && flow.empty() )
    {
        return SliceReply{ {}, "depth bounds the flow walk and there is none — pass flow=back|fwd|both with it, "
                               "or omit depth" };
    }

    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;

    // ── the two-phase spec split, exactly as the CLI: whole spelling first, then HEAD:VAR — skipped when
    //    the var field already carries the variable (then `symbol` is a pure selector).
    std::string_view    selector = symbol;
    std::string_view    varName  = var;
    std::vector<NodeId> matches  = resolveAllByNameQualified( ing, selector );
    if( matches.empty() && var.empty() )
    {
        const std::size_t lastColon = symbol.rfind( ':' );
        if( lastColon != std::string::npos && lastColon > 0 && lastColon + 1 < symbol.size() )
        {
            selector = std::string_view( symbol ).substr( 0, lastColon );
            varName  = std::string_view( symbol ).substr( lastColon + 1 );
            matches  = resolveAllByNameQualified( ing, selector );
        }
    }
    if( matches.empty() )
    {
        return SliceReply{ {}, "symbol not found: " + mcprefuse::cappedEcho( symbol )
                               + " (tried the whole spelling as a selector, then HEAD:VAR)"
                               + mcprefuse::atSeedClause( ing, symbol ) };   // "" for a plain name
    }

    // ── §A6a ambiguity refusal, the CLI's own posture: a slice reads exactly ONE body ─────────────────
    if( matches.size() > 1 )
    {
        const Graph& g = ix.g;
        const std::vector<EditCheckGroup> groups = editCheckGroups( ing, g, matches );
        std::string spellings;
        const std::size_t shownCount = std::min<std::size_t>( groups.size(), kEditCheckSpellingsShown );
        for( std::size_t groupIndex = 0; groupIndex < shownCount; ++groupIndex )
        {
            spellings += ( groupIndex ? ", " : "" ) + groups[ groupIndex ].spelling;
        }
        if( groups.size() > shownCount )
        {
            spellings += " (+" + std::to_string( groups.size() - shownCount ) + " more)";
        }
        return SliceReply{ {}, "'" + std::string( selector ) + "' matches " + std::to_string( matches.size() )
                               + " definitions — a slice reads exactly ONE body, so an ambiguous selector is refused, "
                                 "never silently narrowed. Qualify one: " + spellings
                               + " — or seed by location with symbol=@FILE:LINE" };
    }

    const NodeId  focus = matches[0];
    const Symbol& sym   = ing.symbols[ focus ];

    // ── served-language gate — an honest refusal, never an empty success ──────────────────────────────
    const slicev::SliceFam fam = slicev::sliceFamilyOf( sym.lang );
    if( fam == slicev::SliceFam::None )
    {
        return SliceReply{ {}, std::string( "slice not served for " ) + langTag( sym.lang ) + " yet (served: "
                               + slicev::kSliceServedList + ") — the def-use classification is a verified per-grammar "
                                 "parent-kind read, and this language's has not been built" };
    }

    // ── read + re-parse the ONE file holding the definition ───────────────────────────────────────────
    const std::string& path = diskPath( ing, sym.fileId );
    std::string        src;
    if( std::FILE* in = std::fopen( path.c_str(), "rb" ) )
    {
        char        buf[ 4096 ];
        std::size_t n = 0;
        while( ( n = std::fread( buf, 1, sizeof( buf ), in ) ) > 0 )
        {
            src.append( buf, n );
        }
        std::fclose( in );
    }
    else
    {
        DEGRADED_PATH_ALERT( "mcp slice: definition file unreadable" );
        return SliceReply{ {}, "cannot read " + path + " — the slice re-parses the definition's file and has nothing to walk" };
    }

    const ::TSLanguage* grammar = sliceGrammarForFile( path );
    slicev::SliceScan   scan    = slicev::sliceScanDefinition( src, sym, fam, grammar, varName );
    if( !scan.parseOk )
    {
        DEGRADED_PATH_ALERT( "mcp slice: definition re-parse failed" );
        return SliceReply{ {}, "could not re-parse " + path + " (grammar missing, or the indexed span no longer fits "
                               "the file — a stale index; call any read verb to refresh, or check the CLI --doctor)" };
    }

    // ── unknown-var refusal, offering the sliceable locals (the CLI's wording, field spellings) ───────
    if( !varName.empty() && scan.occ.empty() )
    {
        std::string locals;
        std::vector<slicev::SliceLocal> ordered = scan.locals;
        std::sort( ordered.begin(), ordered.end(), []( const slicev::SliceLocal& a, const slicev::SliceLocal& b )
                   { return a.line != b.line ? a.line < b.line : a.name < b.name; } );
        for( std::size_t localIndex = 0; localIndex < ordered.size(); ++localIndex )
        {
            locals += ( localIndex ? ", " : "" ) + ordered[ localIndex ].name;
        }
        return SliceReply{ {}, "no occurrence of '" + std::string( varName ) + "' in " + sym.name
                               + " — sliceable locals: " + ( locals.empty() ? "(none found)" : locals )
                               + " (a bare symbol lists them with first-def lines)" };
    }

    // ── the @FILE:LINE seed's variable half: pre-pick, or mark the candidates (the CLI contract) ──────
    slicev::SliceSeedInfo seedInfo;
    bool                  seededRun = false;
    std::string           pickedVar;                       // owns the pre-picked name (varName is a view)
    if( !selector.empty() && selector.front() == '@' )
    {
        const AtSeed selSeed = resolveAtSeed( ing, selector.substr( 1 ) );   // the resolver already accepted this spelling
        if( selSeed.fault == AtFault::None )
        {
            seedInfo.spec = std::string( selector.substr( 1 ) );
            seededRun     = true;
            if( varName.empty() )
            {
                seedInfo.seedVars     = slicev::sliceSeedLineLocals( scan, selSeed.line );
                seedInfo.seedVarCount = seedInfo.seedVars.size();
                if( seedInfo.seedVarCount == 1 )
                {
                    pickedVar            = seedInfo.seedVars.front();
                    varName              = pickedVar;
                    seedInfo.varFromSeed = true;
                    scan                 = slicev::sliceScanDefinition( src, sym, fam, grammar, varName );
                }
            }
        }
    }

    // ── the rung-2 flow, when asked for — a flow needs a seed variable ────────────────────────────────
    const bool flowActive = !flow.empty();
    if( flowActive && varName.empty() )
    {
        return SliceReply{ {}, "flow needs a seed variable — a bare symbol lists the sliceable locals; pick one and "
                               "re-call with var (or a SYM:VAR / @FILE:LINE:VAR spelling)" };
    }

    slicev::SliceFlowOut  flowOut;
    slicev::SliceFlowSpec flowSpec;
    flowSpec.dir   = flow == "back" ? slicev::SliceFlowDir::Back
                   : flow == "fwd"  ? slicev::SliceFlowDir::Fwd
                                    : slicev::SliceFlowDir::Both;
    flowSpec.bound = depth > 0 ? std::uint32_t( depth ) : slicev::kSliceFlowDefaultDepth;
    if( flowActive )
    {
        flowOut      = slicev::sliceFlowCompute( scan, varName, flowSpec.dir, flowSpec.bound );
        flowSpec.out = &flowOut;
    }

    slicev::SliceEmitOpts emit;   // full legend always — the MCP payload stays byte-identical to the CLI default
    emit.flow = flowActive ? &flowSpec : nullptr;
    emit.seed = seededRun ? &seedInfo : nullptr;
    return SliceReply{ slicev::sliceBundleText( ing, root, focus, varName, scan, src, redact, emit ), {} };
}

// ─── T4: fetch_body — the LAZY-BODY verb. The read verbs return signatures + a stable `handle`; this verb
// returns the FULL def source ONLY when the agent asks for it by handle. The MCP posture is
// "names/signatures by default, bodies by handle on request" (the kit default-lean posture, ~90% cut).
//
// fetchBody(root, handle) → outcome: either the body JSON payload, or a JSON-RPC-shaped refusal message. The
// refusals mirror the edit-verbs' staleness discipline — a body is NEVER served against bytes the handle
// wasn't minted from:
//   • malformed handle (not sym#<16hex>@<16hex>) → refuse (agent re-reads to get a fresh handle)
//   • no symbol with that stable id → refuse (the symbol was renamed/removed — refresh via a read verb)
//   • the file can't be re-read → refuse
//   • the file's CURRENT bytes hash ≠ the handle's pinned contentHash → STALE: refuse, "refresh via a read
//     verb", body withheld. This is the free staleness the pinned contentHash buys.
// ─── Feature 2: partial-range fetch_body (octocode) ───────────────────────────────────────────────
//
// RANGE SEMANTICS (documented here and in the fetch_body tools/list description):
//   • start_line / end_line are 1-BASED and INCLUSIVE, and are relative to the BODY — line 1 is the def's
//     FIRST line (the signature line), so lines L..M of a 500-line function is exactly {start_line:L,
//     end_line:M}. (Body-relative, not file-relative: the agent thinks in "the function's line 12", and the
//     numbering is stable regardless of where in the file the def sits.)
//   • CLAMPED to the def's own line span, never OOB: start_line clamps up to 1, end_line clamps down to the
//     body's last line; if start_line > end_line after clamping (or start_line exceeds the body) → a CLEAR
//     out-of-range error, never a slice past the buffer.
//   • Omitting BOTH returns the whole body (backward-compatible with the pre-range fetch_body).
//   • UTF-8-SAFE by construction: the slice boundaries are '\n' bytes (or the body's own [a,b) ends), and a
//     '\n' can never fall inside a multibyte UTF-8 sequence, so a line slice never splits a codepoint. (The
//     final jsonEscape pass is ALSO codepoint-validating, so even a torn byte would degrade to U+FFFD, but
//     line-boundary slicing means we never hand it one.)
//   • DETERMINISTic: a pure function of (body bytes, start_line, end_line) — byte-identical run-to-run and
//     across two processes. The handle staleness contract (contentHash pin) is unchanged and still applies:
//     a stale/malformed/unresolved handle refuses BEFORE any range is considered.

// slice body-relative INCLUSIVE 1-based [startLine, endLine] out of `body` (the full def bytes). Returns the
// byte substring and, via out-params, the CLAMPED line window actually returned + the body's total line
// count. `oob` is set true (and the return is empty) when the requested start is past the last line — the
// caller turns that into a clear error. Line 1 begins at byte 0; line N begins just after the (N-1)th '\n'.
// The last line has no trailing '\n' unless the body itself ends in one (then there is a final empty line,
// which we do NOT count — total lines = (#\n in body) + (body nonempty && !endsWithNewline ? 1 : 0), i.e. the
// human "how many lines of code" count). A single-line def is 1 line.
// NAME: distinct from serialize.h::sliceBodyLines by CONTRACT, not just namespace — that one CLAMPS a start
// past the end DOWN into range; this one REFUSES it (sets `oob`, returns empty) so fetch_body can emit a clear
// out-of-range error. The names diverged on purpose; keep them different so neither is mistaken for the other.
inline std::string sliceBodyLinesOrError( const std::string& body, long long startLine, long long endLine,
                                          long long& clampedStart, long long& clampedEnd, long long& totalLines, bool& oob )
{
    oob = false;
    // total lines: count '\n', plus one for a final non-newline-terminated line.
    long long nl = 0;
    for( char c : body )
    {
        if( c == '\n' )
        {
            ++nl;
        }
    }
    const bool endsNl = !body.empty() && body.back() == '\n';
    totalLines = nl + ( ( !body.empty() && !endsNl ) ? 1 : 0 );
    if( totalLines < 1 )
    {
        totalLines = ( body.empty() ? 0 : 1 );
    }

    // clamp the window to [1, totalLines]; a start past the end is genuinely out of range.
    long long s = startLine < 1 ? 1 : startLine;
    long long e = endLine   < 1 ? 1 : endLine;
    if( totalLines == 0 ) { clampedStart = 1; clampedEnd = 0; oob = ( startLine > 0 ); return {}; }
    if( s > totalLines )  { clampedStart = s; clampedEnd = e; oob = true; return {}; }   // start beyond body → error
    if( e > totalLines )
    {
        e = totalLines; // clamp end down (not an error)
    }
    if( e < s )
    {
        e = s; // degenerate end<start → single line
    }
    clampedStart = s; clampedEnd = e;

    // walk to the byte offset where line `s` begins and where line `e+1` begins (or end of body).
    const auto lineStartByte = [ & ]( long long lineNo ) -> std::size_t
    {
        if( lineNo <= 1 )
        {
            return 0;
        }
        long long seen = 1;                                     // we are at the start of line 1
        for( std::size_t i = 0; i < body.size(); ++i )
        {
            if( body[i] == '\n' )
            {
                ++seen;                                         // the byte AFTER this '\n' starts line `seen`
                if( seen == lineNo )
                {
                    return i + 1;
                }
            }
        }
        return body.size();                                     // past the last line → end of body
    };
    const std::size_t aByte = lineStartByte( s );
    const std::size_t bByte = ( e >= totalLines ) ? body.size() : lineStartByte( e + 1 );
    if( aByte > bByte || bByte > body.size() )
    {
        return {}; // paranoia: never slice out of bounds
    }
    return body.substr( aByte, bByte - aByte );
}

struct FetchOutcome
{
    bool        ok = false;
    int         errCode = -32602;
    std::string message;      // on refusal
    std::string resultJson;   // on success: {handle, name, kind, file, line, bytes, body [, start_line, end_line, total_lines, partial]}
    // V3/RN1: true for exactly ONE refusal — a well-formed handle that resolved against no symbol in this
    // tree. It is the only fault whose cause can be an omitted `path` rather than a rename, so the dispatch
    // arm (which is the only place that knows where the root came from) needs to recognize it. Reported as
    // a discriminator rather than by matching the message text, because a refusal identified by substring
    // is one that silently stops being identified the next time someone improves the wording.
    bool        unresolvedHandle = false;
};

// fetchBody with optional body-relative line range. `hasRange` selects partial mode; when false the whole
// body is returned (the original T4 behavior, byte-identical). See sliceBodyLinesOrError for the range semantics.
// `redact` masks credential shapes in the emitted body text (A3-F3 — the raw-JSON body seam, the highest-
// exposure emission path of all: served straight into a cloud LLM context); null under --no-redact.
// Declared first (defaults live HERE, per the one-declaration rule) so fetchBodyByName below and the
// definition after it can call each other — the name path serves by re-entering the handle path.
inline FetchOutcome fetchBody( const std::string& root, const std::string& handle,
                               long long startLine = 1, long long endLine = 0, bool hasRange = false,
                               RedactCounts* redact = nullptr );

// R2c (the 2026-08-12 usage mine): serve fetch_body for a bare symbol NAME through the SAME lookup path
// find_symbol uses (resolveAllByNameQualified → lowest-id pick, i.e. resolveFocus's convention), then
// RECURSE into fetchBody with the freshly-minted real handle — every staleness/overload guarantee applies
// unchanged, and the result teaches the handle for next time. Disclosed: resolved_from_name always;
// name_defs/other_defs (file:line + handle, capped) when the name has several DISTINCT defs — the honest
// sibling of fetchBody's same-handle overload note. An unknown name refuses with a did-you-mean (the ONE
// shared suggester) plus the find_symbol pointer: a one-shot recovery, never a format lecture.
inline FetchOutcome fetchBodyByName( const std::string& root, const std::string& name,
                                     long long startLine, long long endLine, bool hasRange,
                                     RedactCounts* redact )
{
    // the guard lives HERE so the caller's parse-failure branch is one call: a "sym#"-prefixed string is
    // NEVER treated as a name (a corrupt REAL handle must keep the malformed refusal rather than
    // mis-resolve through a name that happens to match), and an empty string has nothing to look up.
    if( name.rfind( "sym#", 0 ) == 0 || name.empty() )
    {
        FetchOutcome oc;
        oc.ok = false; oc.errCode = -32602;
        oc.message = "malformed handle '" + name + "' (expected sym#<16hex>@<16hex>); call a read verb to obtain a valid handle";
        return oc;
    }

    const McpIndex&           nameIx      = getIndex( root );          // same index a read verb would build
    const std::vector<NodeId> nameMatches = resolveAllByNameQualified( nameIx.ing, name );
    if( nameMatches.empty() )
    {
        FetchOutcome oc;
        oc.ok = false; oc.errCode = -32602;
        oc.message = withDidYouMean( nameIx.ing, name,
                                     "'" + name + "' is neither a handle (sym#<16hex>@<16hex>) nor a known symbol name" )
                   + " — call find_symbol for the handle, or pass the exact definition name (file:name disambiguates)"
                   + mcprefuse::atSeedClause( nameIx.ing, name );   // an @FILE:LINE spelling that faulted carries the at-diagnosis
        return oc;
    }

    // distinct HANDLES across the matches (a decl + def in different files mint different ids);
    // matches ascend by NodeId, so front() is the resolveFocus pick and order is deterministic.
    std::vector<std::string> distinctHandles;
    std::vector<NodeId>      distinctIds;
    for( const NodeId id : nameMatches )
    {
        std::string h2 = handleFor( nameIx, id );
        if( std::find( distinctHandles.begin(), distinctHandles.end(), h2 ) == distinctHandles.end() )
        {
            distinctHandles.push_back( std::move( h2 ) );
            distinctIds.push_back( id );
        }
    }

    FetchOutcome byName = fetchBody( root, distinctHandles.front(), startLine, endLine, hasRange, redact );
    if( byName.ok && !byName.resultJson.empty() && byName.resultJson.front() == '{' )
    {
        std::string disclosure = "\"resolved_from_name\":\"" + mcpdetail::jsonEscape( name ) + "\",";
        if( distinctHandles.size() > 1 )
        {
            disclosure += "\"name_defs\":" + std::to_string( distinctHandles.size() ) + ",\"other_defs\":[";
            constexpr std::size_t kOtherDefCap = 4;   // disclosure, not a listing — cap the tail
            bool first = true;
            for( std::size_t i = 1; i < distinctIds.size() && i <= kOtherDefCap; ++i )
            {
                const Symbol& si = nameIx.ing.symbols[ distinctIds[i] ];
                if( !first )
                {
                    disclosure += ",";
                }
                first = false;
                disclosure += "{\"file\":\"" + mcpdetail::jsonEscape( nameIx.ing.files[ si.fileId ] )
                            + "\",\"line\":" + std::to_string( si.line )
                            + ",\"handle\":\"" + mcpdetail::jsonEscape( distinctHandles[i] ) + "\"}";
            }
            disclosure += "],";
        }
        byName.resultJson.insert( 1, disclosure );
    }
    return byName;
}

inline FetchOutcome fetchBody( const std::string& root, const std::string& handle,
                               long long startLine, long long endLine, bool hasRange,
                               RedactCounts* redact )
{
    FetchOutcome oc;

    // 1. parse the handle strictly — a hand-mutated / garbage handle refuses, never mis-resolves.
    //    R2c (the 2026-08-12 usage mine): a string that fails the parse routes to fetchBodyByName above,
    //    which either serves it as a bare symbol NAME (disclosed) or speaks the malformed-handle /
    //    unknown-name refusal itself — including the "sym#"-prefix guard.
    std::uint64_t idHash = 0, wantContent = 0;
    if( !mcpdetail::parseHandle( handle, idHash, wantContent ) )
    {
        return fetchBodyByName( root, handle, startLine, endLine, hasRange, redact );
    }

    const McpIndex&     ix  = getIndex( root );          // refreshes the index if the tree changed (warm==cold)
    const IngestResult& ing = ix.ing;

    // 2. resolve the STABLE id back to a symbol. A rename/removal makes the id unresolvable → refuse.
    std::vector< NodeId > handleMatches;
    const NodeId f = resolveHandleAll( ix, idHash, handleMatches );
    if( f == kNoNode || f >= ing.symbols.size() )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.unresolvedHandle = true;   // V3/RN1: the dispatch arm may add the omitted-`path` cause to this one
        oc.message = "handle '" + handle + "' does not resolve to any current symbol (it may have been renamed or removed); call a read verb to refresh";
        return oc;
    }

    // 2b. F4 HONESTY: same-scope OVERLOADS share one handle (same path::scope::name, same file → identical
    //     canonId hash). We serve the lowest-id overload's body, but with distinct bodies that is only ONE of
    //     several — never serve it silently. Build an ambiguity note listing the OTHER overloads' file:line so
    //     the agent can disambiguate by reading the specific line (the edit verbs REFUSE the same ambiguity;
    //     a read-only verb can be honest without refusing). Only a genuine body divergence is worth noting, so
    //     collisions whose bodies are byte-identical (a decl + its def) stay silent.
    std::string ambiguityNote;
    if( handleMatches.size() > 1 )
    {
        // do the bodies actually differ? read each colliding symbol's span from its (freshly re-read) file.
        // any read failure or any distinct body → treat as ambiguous (be conservative: prefer a note).
        bool bodiesDiffer = false;
        {
            const Symbol&     s0    = ing.symbols[ handleMatches[0] ];
            bool              rok0  = false;
            const std::string src0  = mcpdetail::readFileBytes( diskPath( ing, s0.fileId ), rok0 );
            const std::string body0 = ( rok0 && s0.sigStartByte < s0.endByte && s0.endByte <= src0.size() )
                                    ? src0.substr( s0.sigStartByte, s0.endByte - s0.sigStartByte ) : std::string{};

            for( std::size_t i = 1; i < handleMatches.size() && !bodiesDiffer; ++i )
            {
                const Symbol&     si    = ing.symbols[ handleMatches[i] ];
                bool              roki  = false;
                const std::string srci  = mcpdetail::readFileBytes( diskPath( ing, si.fileId ), roki );
                const std::string bodyi = ( roki && si.sigStartByte < si.endByte && si.endByte <= srci.size() )
                                        ? srci.substr( si.sigStartByte, si.endByte - si.sigStartByte ) : std::string{};
                if( !rok0 || !roki || bodyi != body0 )
                {
                    bodiesDiffer = true;
                }
            }
        }

        if( bodiesDiffer )
        {
            const Symbol& chosen = ing.symbols[f];
            ambiguityNote = std::to_string( handleMatches.size() ) + " overloads share this handle; showing "
                          + ing.files[ chosen.fileId ] + ":" + std::to_string( chosen.line )
                          + " — disambiguate with path/line. others: ";
            bool anyOther = false;
            for( std::size_t i = 0; i < handleMatches.size(); ++i )
            {
                if( handleMatches[i] == f )
                {
                    continue;
                }
                const Symbol& si = ing.symbols[ handleMatches[i] ];
                if( anyOther )
                {
                    ambiguityNote += ", ";
                }
                ambiguityNote += ing.files[ si.fileId ] + ":" + std::to_string( si.line );
                anyOther = true;
            }
        }
    }

    const Symbol&       s      = ing.symbols[f];
    const std::uint32_t fileId = s.fileId;
    const std::string&  path   = ing.files[ fileId ];

    // 3. re-read the file NOW and verify its bytes still hash to the handle's PINNED contentHash. A mismatch
    //    means the body changed since the handle was minted → STALE: refuse (never serve a stale body).
    bool readOk = false;
    const std::string src = mcpdetail::readFileBytes( path, readOk );
    if( !readOk )
    {
        oc.ok = false; oc.errCode = -32603;
        oc.message = "cannot read file '" + path + "' to fetch body for handle '" + handle + "'";
        return oc;
    }
    const std::uint64_t freshContent = mcpdetail::byteHash( src.data(), src.size() );
    if( freshContent != wantContent )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.message = "stale handle '" + handle + "'; the file '" + path
                   + "' changed since this handle was issued — refresh via any read verb (find_symbol/for/grep), then fetch the new handle";
        return oc;
    }

    // 4. the def span is [sigStartByte, endByte) — the exact span --expand/replace_symbol_body use. Degrade,
    //    never assert: an insane span refuses rather than slicing out of bounds.
    const std::size_t a = s.sigStartByte, b = s.endByte;
    if( !( a < b && b <= src.size() ) )
    {
        oc.ok = false; oc.errCode = -32603;
        oc.message = "definition span for handle '" + handle + "' is invalid (a=" + std::to_string( a )
                   + " b=" + std::to_string( b ) + " size=" + std::to_string( src.size() ) + ")";
        return oc;
    }

    const std::string fullBody( src.data() + a, b - a );

    // 5. optional partial-range slice (Feature 2). No range → the whole body (backward-compatible). A range
    //    with a start past the last line is a CLEAR out-of-range refusal, never an out-of-bounds slice.
    std::string body = fullBody;
    long long   clampedStart = 1, clampedEnd = 0, totalLines = 0;
    bool        isPartial = false;
    if( hasRange )
    {
        bool oob = false;
        body = sliceBodyLinesOrError( fullBody, startLine, endLine, clampedStart, clampedEnd, totalLines, oob );
        if( oob )
        {
            oc.ok = false; oc.errCode = -32602;
            oc.message = "line range start " + std::to_string( startLine ) + " is out of bounds for handle '"
                       + handle + "' (the body has " + std::to_string( totalLines )
                       + " line" + ( totalLines == 1 ? "" : "s" ) + "); request a start_line within [1, "
                       + std::to_string( totalLines ) + "]";
            return oc;
        }
        // a range that (after clamping) covers the whole body is reported partial=false so callers can tell.
        isPartial = !( clampedStart == 1 && clampedEnd == totalLines );
    }
    else
    {
        // still report total_lines for a full fetch so an agent can decide whether to re-fetch a range next time.
        long long nl = 0;
        for( char c : fullBody )
        {
            if( c == '\n' )
            {
                ++nl;
            }
        }
        const bool endsNl = !fullBody.empty() && fullBody.back() == '\n';
        totalLines   = nl + ( ( !fullBody.empty() && !endsNl ) ? 1 : 0 );
        if( totalLines < 1 )
        {
            totalLines = ( fullBody.empty() ? 0 : 1 );
        }
        clampedStart = 1; clampedEnd = totalLines;
    }

    // A3-F3: redact credential shapes from the emitted body text. AFTER the range slice (a secret
    // is single-line and the slice is line-bounded, so no secret straddles the cut) and BEFORE the byte
    // count below, so `bytes` reports exactly what is served; no-op when redact is null (--no-redact).
    redactInPlace( body, redact );

    // L3: field-notes parity for the "body" verb. fetch_body serves JSON (not the for/exemplar XML), so a
    // matching symbol's notes ride a JSON `notes` array of {d,text} — the same (date,text) the <note> children
    // carry. Keyed by THIS symbol's canonical id; jsonEscape neutralizes hostile text. An empty/absent notes
    // file leaves `notesJson` empty → the key is omitted → the payload is byte-identical (the inertness contract).
    std::string notesJson;
    {
        const notes::NoteIndex ni    = notes::loadNoteIndex( root );
        const std::string      canon = canonicalId( relForHash( ing.files[ fileId ], ni.root ), s.scope, s.name );   // D5: root-relative note key
        if( const auto* hits = ni.find( canon ) )
        {
            notesJson = ",\"notes\":[";
            bool first = true;
            for( std::uint32_t i : *hits )
            {
                const notes::Note& n = ni.notes[i];
                if( !first )
                {
                    notesJson += ",";
                }
                // provenance parity with the <note sha= branch=> XML attrs (serialize.h::appendOneNote) —
                // OMITTED keys on a legacy/unstamped note, never emitted empty, and abbreviated (shortSha)
                // to match the terse XML surfacing.
                notesJson += "{\"d\":\"" + mcpdetail::jsonEscape( n.date ) + "\",\"text\":\"" + mcpdetail::jsonEscape( n.text ) + "\"";
                if( !n.sha.empty() )
                {
                    notesJson += ",\"sha\":\"" + mcpdetail::jsonEscape( notes::shortSha( n.sha ) ) + "\"";
                    if( !n.branch.empty() )
                    {
                        notesJson += ",\"branch\":\"" + mcpdetail::jsonEscape( n.branch ) + "\"";
                    }
                }
                notesJson += "}";
                first = false;
            }
            notesJson += "]";
        }
    }

    // M12 (capture-audit-2026-09-04, lane L9): the "file" key is DISPLAY, distinct from `path` above (which
    // stays untouched — it feeds readFileBytes and the error messages above, i.e. real disk I/O). Before
    // this fix it printed "./src/graph.h" on a relative root; every other MCP verb's "file" key is already
    // root-relative (see e.g. the situJPathRel/ccRel/pathForJ lambdas earlier in this file).
    const bool         fbSingleRoot = ing.realPaths.empty();
    const std::string  fbDisplayPath = fbSingleRoot ? std::string( sarif::rootRelativeUri( path, sarif::rootPrefixOf( root ) ) ) : path;

    oc.ok = true;
    oc.resultJson = std::string( "{\"handle\":\"" ) + mcpdetail::jsonEscape( handle )
                  + "\",\"name\":\"" + mcpdetail::jsonEscape( s.name )
                  + "\",\"kind\":\"" + symTag( s.kind )
                  + "\",\"file\":\"" + mcpdetail::jsonEscape( fbDisplayPath )
                  + "\",\"line\":" + std::to_string( s.line )
                  + ",\"start_line\":" + std::to_string( clampedStart )
                  + ",\"end_line\":" + std::to_string( clampedEnd )
                  + ",\"total_lines\":" + std::to_string( totalLines )
                  + ",\"partial\":" + ( isPartial ? "true" : "false" )
                  + ",\"bytes\":" + std::to_string( body.size() )
                  + ",\"body\":\"" + mcpdetail::jsonEscape( body ) + "\""
                  + ( ambiguityNote.empty() ? std::string{}
                        : ( ",\"ambiguous_handle\":" + std::to_string( handleMatches.size() )
                          + ",\"ambiguity_note\":\"" + mcpdetail::jsonEscape( ambiguityNote ) + "\"" ) )
                  + notesJson   // L3: field notes on this symbol (omitted when none)
                  + "}";
    return oc;
}

// ─── A4-R3: batch retrieval verb — one-turn context sweep ────────────────────────────────────────
//
// N heterogeneous READ sub-queries answered in ONE call, so an MCP agent pays a single round-trip for
// a whole sweep instead of one per question (the deterministic $0 counterpart of Windsurf Fast Context /
// Cognition SWE-grep). Each sub-query REUSES the exact text-builder its
// standalone verb uses (forTaskText/grepHitsJson/symbolQueryJson/impactText/usesText/mentionsJson/…) —
// no verb logic is reimplemented, so a batched answer is byte-identical to the same standalone verb call.
//
// Scope: the READ set only — NOT the edit verbs (side effects) and NOT quality_baseline (writes a
// sidecar). quality_delta is also excluded (a heavy both-trees clone pass, out of place in a fast sweep).
inline constexpr std::size_t kBatchCap = 16;   // max sub-queries processed per batch; excess is REPORTED, never silently dropped

// ─── §B6 M14: the batch-served verb registry ─────────────────────────────────────────────────────────────
//
// The set batch serves, as a TABLE rather than as a sentence inside tools/list and a second sentence inside
// runBatchSub's unknown-sub-verb message. The tools/list stanza used to hand-count its own exclusion
// parenthetical ("NOT the edit or quality_baseline verbs" — 4 verbs, where the true excluded set is 15), and
// the two ALIASES `callers`/`callees` were served but documented nowhere. Both facts now come from here:
// mcp.h derives the excluded COUNT from kMcpVerbCount minus this table (a static_assert holds the tools/list
// literal to it), and the unknown-sub-verb refusal lists these names instead of restating them.
inline constexpr std::string_view kBatchServedVerbs[] = {
    "for", "grep", "find_symbol", "find_referencing_symbols", "impact", "uses", "mentions",
    "analyze", "lego", "owners", "cochange", "path_between", "exemplar", "fetch_body",
    // P17 (capture-audit 2026-09-04, lens 8 #17): slice and edit_check. Both are READ-ONLY, and they are
    // the two an agent most wants in the SAME turn as callers/uses — "what did I just change, who calls it,
    // where does the value flow, did the contract move". slice was excluded as "a per-definition on-disk
    // re-parse"; that is one file read, cheaper than the grep sub-query already in the set. edit_check is a
    // qheadsnap cache read on a warm tree. The PREVIEW half of edit_check stays out: new_body is not in
    // kBatchSubQueryFields, so a batched preview refuses as an undeclared field rather than quietly
    // building a spliced tree inside a fast sweep.
    "slice", "edit_check",
};

// Dispatch-only synonyms: `callers` == find_referencing_symbols, `callees` == find_symbol. They are NOT
// separate verbs (no separate answer, no separate advertisement) — they exist because those two are the
// names an agent reaches for, and they are named here so "what does batch accept" has one answer.
inline constexpr std::string_view kBatchVerbAliases[] = { "callers", "callees" };

inline constexpr std::size_t kBatchServedCount = std::size( kBatchServedVerbs );

// The batch arm's paging verdict: the sub-query's window refusal, but only for the two sub-verbs that
// actually CONSUME a window (grep and impact) — "" for every other verb and for a valid window. A named
// helper rather than three more conditions inside runBatchSub's dispatch chain, which is already this
// file's most complex function: "which sub-verbs page, and is this one's window valid" is one question,
// and it belongs beside the served-verb registry above, not in the middle of a 14-arm if/else.
//
// A bad window is this SUB-QUERY's own inline error (ok="0" err="…"), never the whole batch's — the batch
// contract for every other refusal, so a paging typo in query 3 never costs the caller queries 1, 2 and 4.
inline std::string batchPageRefusal( std::string_view verb, const McpPageParse& page )
{
    if( page.refusal.empty() )
    {
        return {};
    }
    return ( verb == "grep" || verb == "impact" || verb == "uses" ) ? page.refusal : std::string{};   // LB-G: uses pages too
}

// The served set as ONE list (registry + the two aliases), for the membership test, the near-miss pool and
// the refusal's own listing — three uses that must never disagree about what batch answers.
inline std::vector<std::string_view> batchKnownVerbs()
{
    std::vector<std::string_view> known( std::begin( kBatchServedVerbs ), std::end( kBatchServedVerbs ) );
    known.insert( known.end(), std::begin( kBatchVerbAliases ), std::end( kBatchVerbAliases ) );
    return known;
}

// §B6 M9 (batch half): "" when `verb` IS served, else name it, offer the near-miss, and list the served set
// FROM THE REGISTRY rather than from a hand-copied slash-list that can drift from what the chain dispatches.
//
// W3FIX M4 made it a named function rather than the dispatch chain's fall-through `else`, because the ORDER
// now matters: an unknown sub-verb must be reported BEFORE its arguments are judged, since it has no schema
// to judge them against — and "unknown sub-verb" is the actionable half of that request's problem anyway.
inline std::string unknownSubVerbRefusal( std::string_view verb )
{
    const std::vector<std::string_view> known = batchKnownVerbs();
    if( std::find( known.begin(), known.end(), verb ) != known.end() )
    {
        return {};
    }

    std::string msg = "unknown sub-verb '" + mcprefuse::cappedEcho( verb ) + "'";
    if( const std::string near = mcprefuse::nearestName( known, verb ); !near.empty() )
    {
        msg += " (did you mean '" + near + "'?)";
    }
    msg += " — batch serves read verbs only: " + mcprefuse::joinClauses( known, "/" );
    return msg;
}

struct BatchSub
{
    std::string verb;      // the requested sub-verb, echoed back (escaped) even when unknown
    std::string payload;   // the sub-answer body (XML or JSON, verbatim from the reused builder); "" on error
    bool        ok = false;
    std::string err;       // human-readable reason when !ok (missing arg / not found / unknown sub-verb)
};

// Answer ONE sub-query object (its raw JSON substring) against `root`, reusing the standalone verb's
// builder. `topK`/`stable` mirror the server's run params; `redactPtr` threads the per-request redaction
// tally into the body/doc-emitting verbs exactly as the standalone dispatch does. Never throws for a
// resolvable-but-empty result — that becomes ok=false with an explanatory err, never a whole-batch failure.
inline BatchSub runBatchSub( const std::string& root, const std::string& obj, int topK, bool stable, RedactCounts* redactPtr )
{
    using mcpdetail::findString;

    BatchSub r;

    // W3FIX H5, the SECOND arm: the identical guarded string reader the live arm uses, so a wrong-shaped
    // sub-query argument (`{"verb":"grep","pattern":["a"]}`) refuses here too instead of reading as absent
    // and reporting the field missing. `strArg` remembers the first refusal; declaration order is the
    // reporting order, and it is the same order as the live arm's.
    std::string shapeRefusal;
    const auto  strArg = [ & ]( const char* field ) -> std::string
    {
        const McpStringArg a = mcpStringArg( obj, field );
        if( shapeRefusal.empty() && !a.refusal.empty() )
        {
            shapeRefusal = a.refusal;
        }
        return a.value;
    };

    r.verb = strArg( "verb" );

    const std::string symbol  = strArg( "symbol" );
    const std::string pattern = strArg( "pattern" );
    const std::string task    = strArg( "task" );
    const std::string type    = strArg( "type" );
    const std::string handle  = strArg( "handle" );
    const std::string kind    = strArg( "kind" );
    const std::string grepInTyped = strArg( "in" );   // P3-4: the grep sub-query's span-tier hatch
    const std::string var     = strArg( "var" );      // P17: the slice sub-query's variable half
    const std::string flow    = strArg( "flow" );     // P17: back|fwd|both — validated inside sliceText
    const std::string from    = strArg( "from" );
    const std::string to      = strArg( "to" );
    const std::string file    = strArg( "file" );

    // W3FIX M5, the SECOND arm: the sub-query's range bounds through the same guarded numeric reader, so
    // `start_line:3.9` refuses here exactly as it does live instead of truncating to 3 and answering about a
    // different line span.
    const auto intArg = [ & ]( const char* field, long long least, long long most ) -> McpIntArg
    {
        const McpIntArg a = mcpIntArg( obj, field, least, most );
        if( shapeRefusal.empty() && !a.refusal.empty() )
        {
            shapeRefusal = a.refusal;
        }
        return a;
    };
    const McpIntArg depthArg  = intArg( "depth", 1, 32 );   // P17: the slice flow walk's bound (sliceText pairs it with flow)
    const McpIntArg startArg  = intArg( "start_line", 1, kMcpPageValueMax );
    const McpIntArg endArg    = intArg( "end_line",   1, kMcpPageValueMax );
    const long long startLine = startArg.value;
    const long long endLine   = endArg.value;
    const bool      hasStart  = startArg.isPresent;
    const bool      hasEnd    = endArg.isPresent;

    const auto bad = [ & ]( std::string m ) -> BatchSub { r.ok = false; r.err = std::move( m ); r.payload.clear(); return r; };

    // §B6 M7: the missing-required-field refusal comes from the SHARED table (mcprefusal.h), the same one
    // the live server arm renders — this arm used to say "missing pattern" where the live arm said "missing
    // required field: pattern" and the CLI named the flag, the problem AND an example. `isPresent` is the
    // only per-arm part: here it reads this sub-query object.
    const auto argPresent = [ & ]( std::string_view field ) -> bool
    { return !findString( obj, std::string( field ).c_str() ).empty(); };
    const auto missingField = [ & ]( std::string_view verb ) -> std::string
    { return mcprefuse::missingFieldRefusal( verb, argPresent ); };

    // §B6 M8 + verifier N7: the not-found refusals echo the spelling, carry a near-miss AND carry the verb's
    // trailing guidance clause — this arm dropped that clause on three verbs while the live arm kept it (one
    // condition, two lengths). All three halves now come from mcprefusal.h, keyed by the verb.
    const auto symbolMissing = [ & ]( std::string_view verb, std::string_view spelling ) -> std::string
    { return mcprefuse::notFound( getIndex( root ).ing, "symbol", spelling, mcprefuse::notFoundHintFor( verb, "symbol" ) ); };

    // Verifier N2/N8: the paging window, validated ONCE for the two sub-verbs that consume it.
    const McpPageParse pageParse = mcpPageArgs( obj );
    if( const std::string pageErr = batchPageRefusal( r.verb, pageParse ); !pageErr.empty() )
    {
        return bad( pageErr );
    }

    if( r.verb.empty() )
    {
        return bad( shapeRefusal.empty()
                  ? "missing required field: verb — every batch sub-query names one read verb, e.g. "
                    "verb=\"grep\" (batch serves: " + mcprefuse::joinClauses(
                        std::vector<std::string_view>( std::begin( kBatchServedVerbs ), std::end( kBatchServedVerbs ) ), "/" ) + ")"
                  : shapeRefusal );   // `verb:5` is PRESENT-but-wrong-shaped, not missing (W3FIX H5/M8)
    }

    // W3FIX H5: a wrong-SHAPED sub-query argument refuses before the verb serves a default — checked at the
    // same point in the chain as the live arm's shapeRefusal gate (before verb dispatch), so a given request
    // gets the same refusal through either arm.
    if( !shapeRefusal.empty() )
    {
        return bad( shapeRefusal );
    }

    // §B6 M9 / W3FIX M4 — in this order, deliberately: an unknown sub-verb first (it has no schema for the
    // next check to use), then an argument the batch ITEM schema does not declare, with the same near-miss
    // treatment the live arm gives an undeclared tools/call field.
    if( const std::string verbErr = unknownSubVerbRefusal( r.verb ); !verbErr.empty() )
    {
        return bad( verbErr );
    }
    if( const std::string fieldErr = mcpUnknownFieldRefusal( obj, r.verb, mcprefuse::kBatchSubQueryFields );
        !fieldErr.empty() )
    {
        return bad( fieldErr );
    }

    if( r.verb == "for" )
    {
        if( task.empty() )
        {
            return bad( missingField( "for" ) );
        }
        r.payload = forTaskText( root, task, redactPtr );
        if( r.payload.empty() )
        {
            return bad( "no symbols found" );
        }
    }
    else if( r.verb == "grep" )
    {
        if( pattern.empty() )
        {
            return bad( missingField( "grep" ) );
        }
        // P3-4/P6-1: the span-tier hatch, through the SAME closed-value reader the live arm uses — so a
        // typo refuses here as it does there, and the ack's "both callers updated" is finally true.
        GrepIn batchGrepIn = GrepIn::Code;
        if( const std::string inRefusal = grepInModeFromArg( grepInTyped, batchGrepIn ); !inRefusal.empty() )
        {
            return bad( inRefusal );
        }
        r.payload = grepHitsJson( root, pattern, pageParse.page, batchGrepIn );   // N8: the batch arm pages grep too
    }
    else if( r.verb == "find_symbol" || r.verb == "callees" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "find_symbol" ) );
        }
        r.payload = symbolQueryJson( root, symbol, false );
        if( r.payload.empty() )
        {
            return bad( symbolMissing( "find_symbol", symbol ) );
        }
    }
    else if( r.verb == "find_referencing_symbols" || r.verb == "callers" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "find_referencing_symbols" ) );
        }
        r.payload = symbolQueryJson( root, symbol, true );
        if( r.payload.empty() )
        {
            return bad( symbolMissing( "find_referencing_symbols", symbol ) );
        }
    }
    else if( r.verb == "impact" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "impact" ) );
        }
        r.payload = impactText( root, symbol, pageParse.page );   // §B6 M4: the batch arm honors the SAME window
        if( r.payload.empty() )
        {
            return bad( symbolMissing( "impact", symbol ) );
        }
    }
    else if( r.verb == "uses" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "uses" ) );
        }
        // V2-1: refuse a qualified spelling whose bare name IS defined (shared guard, see usesSelectorRefusal).
        if( const std::string refusal = usesSelectorRefusal( getIndex( root ).ing, symbol ); !refusal.empty() )
        {
            return bad( refusal );
        }
        r.payload = usesText( root, symbol, pageParse.page );   // LB-G: the batch arm honors the SAME window (the impact precedent)
    }
    else if( r.verb == "mentions" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "mentions" ) );
        }
        // §B11.1: the batch arm refuses a qualified spelling identically — the same clone-seam drift V2-1's
        // own header warns about (its first landing guarded one dispatch site of two).
        if( const std::string refusal = qualifiedSelectorRefusal( getIndex( root ).ing, symbol, "--mentions=" ); !refusal.empty() )
        {
            return bad( refusal );
        }
        r.payload = mentionsJson( root, symbol );
        if( r.payload.empty() )
        {
            return bad( symbolMissing( "mentions", symbol ) );
        }
    }
    else if( r.verb == "analyze" )
    {
        r.payload = analyzeToString( root, topK, stable );
        if( r.payload.empty() )
        {
            return bad( "no indexed symbols at path (empty corpus or unreadable directory)" );
        }
    }
    else if( r.verb == "lego" )
    {
        if( type.empty() )
        {
            return bad( missingField( "lego" ) );
        }
        r.payload = legoText( root, type, redactPtr );           // D8 fix: "" now means genuine not-found only (zero implementors is real content)
        if( r.payload.empty() )
        {
            return bad( mcprefuse::notFound( getIndex( root ).ing, "type", type ) );
        }
    }
    else if( r.verb == "owners" )
    {
        // §B11.1: same guard, same sentence — `symbol` is optional here, and an empty one has no colon.
        if( const std::string refusal = qualifiedSelectorRefusal( getIndex( root ).ing, symbol, "--owners=" ); !refusal.empty() )
        {
            return bad( refusal );
        }
        r.payload = ownersText( root, symbol );      // symbol optional (empty = all files)
        if( r.payload.empty() )
        {
            return bad( symbol.empty() ? std::string( "no git history for this tree (owners is mined from git; not a repo, or no commits)" )
                                       : symbolMissing( "owners", symbol ) );   // N7: the hint comes from the table row
        }
    }
    else if( r.verb == "cochange" )
    {
        if( file.empty() )
        {
            return bad( missingField( "cochange" ) );
        }
        r.payload = cochangePartnersJson( root, file );
        if( r.payload.empty() )
        {
            return bad( mcprefuse::fileNotFound( getIndex( root ).ing, file ) );
        }
    }
    else if( r.verb == "path_between" )
    {
        if( from.empty() || to.empty() )
        {
            return bad( missingField( "path_between" ) );
        }
        r.payload = pathText( root, from, to );
        if( r.payload.empty() )
        {
            return bad( pathEndpointRefusal( getIndex( root ).ing, from, to ) );
        }
    }
    else if( r.verb == "exemplar" )
    {
        const std::string arg = !kind.empty() ? kind : task;
        if( arg.empty() )
        {
            return bad( missingField( "exemplar" ) );
        }
        r.payload = exemplarText( root, arg, redactPtr );
        if( r.payload.empty() )
        {
            return bad( "no matching exemplar (no symbol of that kind, or the task matched nothing)" );
        }
    }
    else if( r.verb == "slice" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "slice" ) );
        }
        // sliceText owns the WHOLE contract (resolution, the @FILE:LINE seed, flow/depth pairing, every
        // refusal) — the same call the live arm makes, so a batched slice cannot become a second slice.
        const SliceReply sr = sliceText( root, symbol, var, flow, depthArg.isPresent ? int( depthArg.value ) : 0, redactPtr );
        if( sr.payload.empty() )
        {
            return bad( sr.refusal );
        }
        r.payload = sr.payload;
    }
    else if( r.verb == "edit_check" )
    {
        if( symbol.empty() )
        {
            return bad( missingField( "edit_check" ) );
        }
        // No new_body: the batched form is the post-hoc question only (see kBatchServedVerbs).
        const EditCheckReply er = editCheckText( root, symbol );
        if( er.payload.empty() )
        {
            return bad( er.refusal );
        }
        r.payload = er.payload;
    }
    else if( r.verb == "fetch_body" )
    {
        if( handle.empty() )
        {
            return bad( missingField( "fetch_body" ) );
        }
        const bool         hasRange = hasStart || hasEnd;
        const long long    s        = hasStart ? startLine : 1;
        const long long    e        = hasEnd   ? endLine   : ( hasStart ? (long long)0x7fffffff : 0 );
        const FetchOutcome fo       = fetchBody( root, handle, s, e, hasRange, redactPtr );
        if( !fo.ok )
        {
            return bad( fo.message );
        }
        r.payload = fo.resultJson;
    }
    else
    {
        // Unreachable by construction: unknownSubVerbRefusal above already refused anything outside
        // kBatchServedVerbs + kBatchVerbAliases, and every member of those has an arm. If a verb joins the
        // registry without one, THIS is the honest failure — never a silent ok="1" with an empty payload.
        DEGRADED_PATH_ALERT( "batch: a verb in the served registry has no dispatch arm" );
        return bad( "batch cannot answer '" + r.verb + "' — it is in the served registry but has no dispatch "
                    "arm (a ripwire bug: kBatchServedVerbs and runBatchSub have drifted)" );
    }

    r.ok = true;
    return r;
}

// A4-R3: wrap arbitrary text in a CDATA section, splitting any interior "]]>" across the boundary
// ("]]>" → "]]]]><![CDATA[>") so a sub-answer that itself contains "]]>" can never terminate the section
// early. This is what keeps the whole batch payload one WELL-FORMED XML document regardless of whether a
// sub-answer is XML (for/impact/uses/…) or JSON (grep/find_symbol/…) — every payload rides verbatim inside
// CDATA, so extracting a <q>'s CDATA reproduces its standalone-verb output byte-for-byte.
inline std::string batchCdata( const std::string& s )
{
    std::string out = "<![CDATA[";
    std::size_t pos = 0;
    for( ;; )
    {
        const std::size_t hit = s.find( "]]>", pos );
        if( hit == std::string::npos ) { out.append( s, pos, std::string::npos ); break; }
        out.append( s, pos, hit - pos );
        out += "]]]]><![CDATA[>";
        pos = hit + 3;
    }
    out += "]]>";
    return out;
}

// A4-R3: serialize the completed sub-answers into ONE batch payload. DEDUP (the "natural seam for
// within-reply dedup" the audit named): if sub-answer j's payload is byte-identical to an earlier OK
// sub-answer i's, j emits `<dup-of q="i"/>` instead of repeating the block — conservative (exact same
// payload only), deterministic (first earlier match wins), and it never mis-references (only an exact
// byte match dedups). `requested` is the sub-query count BEFORE the cap (so an over-cap batch is honest:
// n < requested with capped="1"); `cap` is kBatchCap.
inline std::string batchText( const std::vector<BatchSub>& subs, std::size_t requested, std::size_t cap )
{
    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view sv ) -> std::string { return std::string( escapeXml( sv, esc ) ); };

    std::string out;
    out += "<batch n=\"" + std::to_string( subs.size() )
         + "\" requested=\"" + std::to_string( requested )
         + "\" cap=\"" + std::to_string( cap ) + "\"";
    if( requested > cap )
    {
        out += " capped=\"1\"";
    }
    out += "><!-- ripwire batch: N read sub-queries answered in one sweep. Each <q> carries i=index, "
           "verb=sub-verb, ok=1|0; the sub-answer rides verbatim in CDATA (a mix of XML and JSON payloads); "
           "<dup-of q=\"i\"/> means this payload is byte-identical to the one already emitted at index i; "
           "ok=0 carries err= and no payload. Over-cap batches set capped=\"1\" with n<requested. -->";

    for( std::size_t i = 0; i < subs.size(); ++i )
    {
        const BatchSub& sub = subs[i];
        out += "<q i=\"" + std::to_string( i ) + "\" verb=\"" + ex( sub.verb ) + "\" ok=\"" + ( sub.ok ? "1" : "0" ) + "\"";
        if( !sub.ok )
        {
            out += " err=\"" + ex( sub.err ) + "\"/>";
            continue;
        }
        // dedup: first earlier OK sub-answer with an identical payload (exact byte match only).
        std::size_t dupOf = i;
        for( std::size_t j = 0; j < i; ++j )
        {
            if( subs[j].ok && subs[j].payload == sub.payload ) { dupOf = j; break; }
        }
        if( dupOf != i )
        {
            out += "><dup-of q=\"" + std::to_string( dupOf ) + "\"/></q>";
        }
        else
        {
            out += ">" + batchCdata( sub.payload ) + "</q>";
        }
    }
    out += "</batch>";
    return out;
}

}   // namespace rw
