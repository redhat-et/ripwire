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
    v += "<tests n=\"" + std::to_string( facts.tests.size() ) + "\">";
    // M21(b) / lens 2 L2 (capture-audit 2026-09-04): this section is titled "tests-to-run" and named files
    // that are not commands, while --situ / --pr-context / --affected — which compute the SAME list from the
    // SAME facts — carried run="bash test/…" for those same files. The packet whose whole purpose is to be
    // read by the NEXT session was the one that said least. Built here, inside the section's scope, because
    // TestRunnerIndex is lazy: a packet with no test row reads no runner script.
    const rw::TestRunnerIndex hoRunners( ing );
    const auto                hoEsc = [ & ]( std::string_view t ) { return std::string( escapeXml( t, esc ) ); };
    for( const std::uint32_t f : facts.tests )
    {
        v += "<t p=\"";
        v += escapeXml( hoPathRel( f ), esc );
        v += "\"";
        v += rw::runAttrDisclosed( hoRunners, f, hoEsc );
        v += "/>";
    }
    v += "</tests></verified>";

    // ── heuristic rows, priority order (dropped TAIL-FIRST under a budget) ───────────────────────────
    struct Row { std::string xml; };
    std::vector<Row> rows;
    std::size_t nCochange = 0;
    for( const auto& [ f, deg ] : facts.forgotten )
    {
        if( nCochange++ >= kHandoffCochangeRows )
        {
            break;
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
    std::vector<notes::Note> committed = notes::readNotesRelative( notes::notesPath( root ), root );
    notes::sortNotes( committed );
    std::size_t nNotes = 0;
    for( const notes::Note& n : committed )
    {
        bool touches = facts.changed.empty();   // clean tree: every committed note is a candidate
        for( const std::uint32_t f : facts.changed )
        {
            if( n.target.rfind( ing.files[f], 0 ) == 0 )
            {
                touches = true;
                break;
            }
        }
        if( !touches || nNotes++ >= kHandoffNoteRows )
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
        std::string doc = "<!-- ripwire handoff: the continuation packet for the NEXT session. <verified> is disk truth "
                          "(branch=/at=<sha>[+dirty]/subject=<commit subject text>, changed files+symbols via git numstat, "
                          "blast_files=transitive dependent files, tests-to-run); ";
        doc += rw::kRunHintLegendClause;   // M21(b): the ONE wording, spliced — never a seventh paraphrase
        doc += "<heuristic> is labeled non-verified suggestion (cochange=usually-edited-together deg=degree, note=committed "
                          ".ripwire_notes row, doc=plan/design pointer s=lexical score for the branch+commit-subject query). "
                          "budget= is the token-budget cap; withheld=1 when heuristic rows were dropped to fit it, withheld_rows= how many "
                          "(the map's spelling: a boolean, the count beside it) — verified rows are never dropped; est_tokens= prices the "
                          "delivered packet in tokens and over_ceiling= is 1 when even the verified floor exceeds budget= (the packet is then "
                          "complete, not trimmed). gitok=0 means the git diff probe failed and changed counts are floors. -->";
        doc += "<handoff";
        doc += at;
        // R-E (2026-08-17 harvest): single-root by construction — the crawl root every p= above is relative to.
        doc += " root=\"";  doc += escapeXml( root, esc );  doc += "\"";
        doc += " branch=\"";
        doc += escapeXml( branch, esc );
        doc += "\" subject=\"";   // M10 (M0-4): was `head=`, but this holds the commit SUBJECT text, not a
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
        doc += "<heuristic n=\"" + std::to_string( keepRows ) + "\">";
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
