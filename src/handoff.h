#pragma once

// handoff.h — `--handoff`: the deterministic continuation packet for the NEXT agent session.
//
// One minified XML document (G4), two hard-labeled sections honoring the honesty contract:
//   <verified>  — disk truth only: branch / HEAD sha (+dirty), the changed files with their symbols,
//                 the transitive blast-radius size, and the tests-to-run rows (same analyses --situ
//                 sections 1–2 run — computeSituationFacts is the ONE implementation).
//   <heuristic> — clearly labeled non-verified suggestions: co-change partners NOT in the diff,
//                 committed .ripwire_notes matching the changed files, and the top plan/design docs
//                 ranked by the SAME lexical scorer --recall uses, with a DISK-DERIVED query (branch
//                 name + last commit subject) — no model, no network, deterministic.
// An empty diff is not an error: the packet still carries branch/sha, notes, and doc pointers — the
// "session died with a clean tree" case is exactly when a handoff is needed.
// `--token-budget=N` composes: heuristic rows are dropped tail-first until the packet fits, and the
// header discloses budget= and withheld= (a truncation is never silent). Verified rows are never
// dropped — a budget that cannot even hold the verified core still emits it (the packet's floor).
// Single-root only for now (multi-root refusal lives at the dispatch site, like --quality-delta).

#include "model.h"
#include "graph.h"
#include "situ.h"        // computeSituationFacts + gitDiffChangedMask — the ONE change-set analysis
#include "notes.h"       // readNotesRelative — committed agent memory, matched to the changed files
#include "lexical.h"     // lexicalScores — the SAME scorer --recall ranks docs with
#include "gitstamp.h"    // atAttr — at="<sha>[+dirty]"
#include "gitmine.h"     // gitCommandLines — byte-safe git pipe reader
#include "serialize.h"   // escapeXml + kMinBytesPerToken
#include "infra/jsonesc.h"     // shSingleQuote
#include <algorithm>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kHandoffDocRows      = 4;   // heuristic doc pointers shown
inline constexpr std::size_t kHandoffNoteRows     = 8;   // heuristic note rows shown
inline constexpr std::size_t kHandoffCochangeRows = 8;   // heuristic co-change rows shown
inline constexpr std::size_t kHandoffSymbolsPerFile = 6; // verified symbols listed per changed file

namespace handoff_detail
{

inline std::string gitOneLine( const std::string& root, const char* args )
{
    const GitCommandLines r = gitCommandLines( "git -C " + shSingleQuote( root ) + " " + args + " 2>/dev/null" );
    return ( r.isStarted && r.status == 0 && !r.lines.empty() ) ? r.lines[0] : std::string();
}

inline bool isMarkdownPath( std::string_view p ) noexcept
{
    return p.size() > 3 && ( p.ends_with( ".md" ) || p.ends_with( ".markdown" ) );
}

} // namespace handoff_detail

inline constexpr const char* kHandoffLegend =
    "<!-- ripwire handoff: the continuation packet for the NEXT session. <verified> is disk truth "
    "(branch=/at=<sha>[+dirty]/subject=<commit subject text>, changed files+symbols via git numstat, "
    "blast_files=transitive dependent files, tests-to-run); "
    "<heuristic> is labeled non-verified suggestion (cochange=usually-edited-together deg=degree, note=committed "
    ".ripwire_notes row, doc=plan/design pointer s=lexical score for the branch+commit-subject query). "
    "branch= is git's own answer, so on a DETACHED head it reads HEAD and detached=1 says so (the commit is at=); "
    "detached= is absent when a branch is checked out. "
    "&lt;heuristic n= candidates= capped=&gt;: n= is the rows in the packet, candidates= how many the three classes "
    "produced before their own per-class caps (cochange 8, notes 8, docs 4), capped=1 when a cap dropped one — so "
    "candidates - n - withheld_rows is what the caps removed and nothing is lost silently. "
    "&lt;t&gt; carries run= wherever a runner is DERIVABLE from real evidence, the same hint situ/test-gate/pr-context print; "
    "absent run= means not derivable, never a guess. "
    "budget= is the token-budget cap; withheld=1 when heuristic rows were dropped to fit it, withheld_rows= how many "
    "(the map's spelling: a boolean, the count beside it) — verified rows are never dropped; est_tokens= prices the "
    "delivered packet in tokens and over_ceiling= is 1 when even the verified floor exceeds budget= (the packet is then "
    "complete, not trimmed). gitok=0 means the git diff probe failed and changed counts are floors. -->";

// M4(a) — THE NOTE-TARGET SET of the verified half: every note-index key that names a file in
// changed ∪ blast, or a symbol defined in one. The two key spellings are serialize.h's OWN pair
// (fileNoteTarget = relForHash, symbolNoteTarget = canonicalIdRelTo), built here rather than approximated,
// because the row this decides is "does the note --for would surface belong in the handoff too" and a
// second rule for that is how the two answers drift.
//
// It replaces a PREFIX test (`n.target.rfind( ing.files[f], 0 ) == 0`) that compared a ROOT-RELATIVE note
// target against a CRAWL-ROOT-PREFIXED path and could only ever match by accident — measured in the
// capture's sandbox as a non-dangling note on a symbol in handoff's own <verified> set producing no row,
// beside withheld="0". Its own function because the packet assembler is already at the complexity bar and
// this is one lookup table with one rule.
inline HashMap<std::string, std::uint8_t> verifiedNoteTargets( const IngestResult& ing, const SituationFacts& facts,
                                                               const std::string& root )
{
    HashMap<std::string, std::uint8_t> targets;
    std::vector<char>                  inVerified( ing.files.size(), 0 );
    for( const std::uint32_t f : facts.changed )     { inVerified[f] = 1; }
    for( const std::uint32_t f : facts.blastRadius ) { inVerified[f] = 1; }
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        if( inVerified[f] )
        {
            targets[ std::string( relForHash( ing.files[f], root ) ) ] = 1;
        }
    }
    for( const Symbol& sym : ing.symbols )
    {
        if( sym.fileId < inVerified.size() && inVerified[ sym.fileId ] )
        {
            targets[ canonicalIdRelTo( ing, sym, root ) ] = 1;
        }
    }
    return targets;
}

// Assemble and print the packet. Returns the process exit code (0 — refusals live at the dispatch site).
inline int writeHandoffPacket( std::FILE* out, const std::string& root, const IngestResult& ing, const Graph& g,
                               std::size_t tokenBudget )
{
    using namespace handoff_detail;
    std::vector<char> esc;   // escapeXml scratch, reused across every attribute
    // R-E (2026-08-17 harvest): single-root only by construction (the caller already refused multi-root),
    // so this always strips — same convention every other lens's pathRel uses (sarif.h).
    const std::string  hoRootPrefix = rw::sarif::rootPrefixOf( root );
    const auto          hoPathRel   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return rw::sarif::rootRelativeUri( ing.files[ fileId ], hoRootPrefix );
    };

    const std::string branch  = gitOneLine( root, "rev-parse --abbrev-ref HEAD" );
    const std::string subject = gitOneLine( root, "log -1 --format=%s" );
    const std::string at      = gitstamp::atAttr( root );

    auto [ changedMask, gitOk ] = gitDiffChangedMask( root, ing );
    if( changedMask.size() != ing.files.size() )
    {
        changedMask.assign( ing.files.size(), 0 );
    }
    const SituationFacts facts = computeSituationFacts( root, ing, g, changedMask );

    // ── verified core (never budget-dropped) ─────────────────────────────────────────────────────────
    std::string v;
    v += "<verified changed=\"" + std::to_string( facts.changed.size() )
       + "\" blast_files=\"" + std::to_string( facts.blastRadius.size() ) + "\">";
    for( const std::uint32_t f : facts.changed )
    {
        v += "<f p=\"";
        v += escapeXml( hoPathRel( f ), esc );
        v += "\">";
        std::size_t shown = 0;
        for( std::size_t i = 0; i < ing.symbols.size() && shown < kHandoffSymbolsPerFile; ++i )
        {
            if( ing.symbols[i].fileId == f )
            {
                v += "<s n=\"";
                v += escapeXml( ing.symbols[i].name, esc );
                v += "\"/>";
                ++shown;
            }
        }
        v += "</f>";
    }
    // M4(b) — the SAME run= hint --situ / --test-gate / --pr-context print for the same file. One spelling
    // (testmap.h::runAttr): a packet whose whole audience is an agent about to resume was the one emitter
    // making its recipient re-derive the command. Absent still means NOT DERIVABLE, never a guess.
    const TestRunnerIndex runners( ing );
    v += "<tests n=\"" + std::to_string( facts.tests.size() ) + "\">";
    for( const std::uint32_t f : facts.tests )
    {
        v += "<t p=\"";
        v += escapeXml( hoPathRel( f ), esc );
        v += "\"";
        v += runAttr( runners, f, [ & ]( std::string_view t ) { return std::string( escapeXml( t, esc ) ); } );
        v += "/>";
    }
    v += "</tests></verified>";

    // ── heuristic rows, priority order (dropped TAIL-FIRST under a budget) ───────────────────────────
    struct Row { std::string xml; };
    std::vector<Row> rows;
    // M4(a) — every heuristic row a class PRODUCED, before its own cap. `n=` on the section is what the
    // packet carries and `withheld_rows=` is what the budget dropped; without this third number a row lost
    // to a per-class cap is invisible, which is exactly how a matching note went missing under withheld="0".
    std::size_t candidates = 0;
    std::size_t nCochange = 0;
    for( const auto& [ f, deg ] : facts.forgotten )
    {
        ++candidates;
        if( nCochange++ >= kHandoffCochangeRows )
        {
            continue;
        }
        char degBuf[32];
        std::snprintf( degBuf, sizeof degBuf, "%.2f", deg );
        std::string r = "<cochange p=\"";
        r += escapeXml( hoPathRel( f ), esc );
        r += "\" deg=\"";
        r += degBuf;
        r += "\"/>";
        rows.push_back( { std::move( r ) } );
    }
    // M4(a) — THE NOTE MATCH. This tested `n.target.rfind( ing.files[f], 0 ) == 0`, and the two strings are
    // in different spellings: a note target is stored ROOT-RELATIVE (notes.h::normalizeNoteTarget) while
    // ing.files[] is CRAWL-ROOT-PREFIXED (arch.h §S2), so the prefix could only match by accident. Measured
    // in the capture's sandbox: a non-dangling note sitting on a symbol in handoff's OWN <verified> set
    // produced no row, beside withheld="0".
    //
    // The fix does not repair the prefix test, it removes it: the note index's OWN keys are built here —
    // the file key and the symbol key, from serialize.h's two rules — for every file in the verified set,
    // and a note matches iff its target IS one of them. Exact, not a prefix, so it cannot drift from what
    // --for/--expand surface. The set is changed ∪ BLAST, not changed alone: a note on a caller you are
    // about to break is precisely what the next session needs and precisely what it cannot see coming.
    const HashMap<std::string, std::uint8_t> verifiedTargets = verifiedNoteTargets( ing, facts, root );
    std::vector<notes::Note> committed = notes::readNotesRelative( notes::notesPath( root ), root );
    notes::sortNotes( committed );
    std::size_t nNotes = 0;
    for( const notes::Note& n : committed )
    {
        // clean tree: nothing is changed and nothing is blast, so every committed note is a candidate —
        // the "session died with a clean tree" case this packet exists for.
        const bool touches = facts.changed.empty() || verifiedTargets.find( n.target ) != verifiedTargets.end();
        if( !touches )
        {
            continue;
        }
        ++candidates;
        if( nNotes++ >= kHandoffNoteRows )
        {
            continue;
        }
        std::string r = "<note target=\"";
        r += escapeXml( n.target, esc );
        r += "\" txt=\"";
        r += escapeXml( n.text, esc );
        r += "\"/>";
        rows.push_back( { std::move( r ) } );
    }
    // doc pointers — the recall scorer over a DISK-DERIVED query; pointers only, never doc bodies
    const std::string recallQuery = branch + " " + subject;
    if( !recallQuery.empty() && recallQuery != " " )
    {
        const std::vector<float> score = lexicalScores( ing, g.outOff, g.outTargets, recallQuery );
        std::vector<std::pair<float, std::uint32_t>> best;   // (max symbol score, fileId) per markdown file
        std::vector<float> fileBest( ing.files.size(), 0.f );
        for( std::size_t i = 0; i < ing.symbols.size(); ++i )
        {
            const std::uint32_t f = ing.symbols[i].fileId;
            fileBest[f] = std::max( fileBest[f], score[i] );
        }
        for( std::uint32_t f = 0; f < ing.files.size(); ++f )
        {
            if( fileBest[f] > 0.f && isMarkdownPath( ing.files[f] ) )
            {
                best.emplace_back( fileBest[f], f );
            }
        }
        std::sort( best.begin(), best.end(), [ & ]( const auto& a, const auto& b )
                   { return a.first != b.first ? a.first > b.first : ing.files[a.second] < ing.files[b.second]; } );
        candidates += best.size();
        for( std::size_t i = 0; i < best.size() && i < kHandoffDocRows; ++i )
        {
            char sBuf[32];
            std::snprintf( sBuf, sizeof sBuf, "%.3f", double( best[i].first ) );
            std::string r = "<doc p=\"";
            r += escapeXml( hoPathRel( best[i].second ), esc );
            r += "\" s=\"";
            r += sBuf;
            r += "\"/>";
            rows.push_back( { std::move( r ) } );
        }
    }

    // ── budget: drop heuristic rows tail-first until the whole packet fits; disclose what was withheld ─
    const auto assemble = [ & ]( std::size_t keepRows, std::size_t withheld )
    {
        std::string doc = kHandoffLegend;
        doc += "<handoff";
        doc += at;
        // R-E (2026-08-17 harvest): single-root by construction — the crawl root every p= above is relative to.
        doc += " root=\"";  doc += escapeXml( root, esc );  doc += "\"";
        doc += " branch=\"";
        doc += escapeXml( branch, esc );
        doc += "\"";
        // M4(c): `git rev-parse --abbrev-ref HEAD` answers the literal string "HEAD" on a detached head —
        // not a branch name. The packet's "disk truth" half read as if a branch called HEAD existed. The
        // sha is already on at=, so the missing fact is only which STATE this is; absent means attached.
        if( branch == "HEAD" )
        {
            doc += " detached=\"1\"";
        }
        doc += " subject=\"";   // M10 (M0-4): was `head=`, but this holds the commit SUBJECT text, not a
                                  // sha — `head=` means a sha on --merge-scout/--stray-content/--stray-content
                                  // --abi; the sha is `at=` above, so this is the one true rename, not a
                                  // second spelling of the same fact.
        doc += escapeXml( subject, esc );
        doc += "\" gitok=\"" + std::string( gitOk ? "1" : "0" ) + "\"";
        if( tokenBudget > 0 )
        {
            // M11: withheld= is a BOOLEAN (the map's spelling); the dropped-row COUNT rides beside it.
            doc += " budget=\"" + std::to_string( tokenBudget ) + "\" withheld=\"" + ( withheld > 0 ? "1" : "0" )
                 + "\" withheld_rows=\"" + std::to_string( withheld ) + "\"";
        }
        doc += ">";
        doc += v;
        doc += "<heuristic n=\"" + std::to_string( keepRows ) + "\" candidates=\"" + std::to_string( candidates )
             + "\" capped=\"" + ( candidates > rows.size() ? "1" : "0" ) + "\">";
        for( std::size_t i = 0; i < keepRows; ++i )
        {
            doc += rows[i].xml;
        }
        doc += "</heuristic></handoff>";
        return doc;
    };

    std::size_t keep = rows.size();
    std::string doc  = assemble( keep, 0 );
    if( tokenBudget > 0 )
    {
        const std::size_t byteCap = std::size_t( double( tokenBudget ) * kMinBytesPerToken );
        while( keep > 0 && doc.size() > byteCap )
        {
            --keep;
            doc = assemble( keep, rows.size() - keep );
        }
        if( keep == 0 && doc.size() > byteCap )
        {
            doc = assemble( 0, rows.size() );   // verified floor — over budget, disclosed, never silent
        }
    }
    // M11: the PRICED ROOT — est_tokens= at the same conservative rate the byte cap above is derived from, so
    // est_tokens <= budget exactly when the packet fits; over_ceiling="1" when even the verified floor does not.
    {
        const std::size_t legendEnd = doc.find( "<handoff" );
        std::size_t       estTokens = 0;
        std::string       rootAttrs = pricedRootAttr( doc.size(), kMinBytesPerToken, 0, &estTokens );
        if( tokenBudget > 0 && estTokens > tokenBudget ) { rootAttrs += " over_ceiling=\"1\""; }
        spliceRootAttrs( doc, rootAttrs, legendEnd == std::string::npos ? 0 : legendEnd );
    }
    std::fwrite( doc.data(), 1, doc.size(), out );
    std::fputc( '\n', out );
    return 0;
}

} // namespace rw
