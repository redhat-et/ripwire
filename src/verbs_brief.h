#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_brief.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

#include "brief.h"        // rw::brief::composeBrief — the eight sections and the size fit (shared with the MCP `brief` verb)
#include "infra/emit.h"   // rw::emitRaw
#include <cstdint>
#include <string_view>
#include <variant>

// verbs_brief.h — the CLI `--brief="TASK"` handler, and `--handoff=TASK`, which prints the same brief after the packet. parseArgs set forTask to the brief's task, so the run was prepared as a
// --for run; this handler runs --for through its own entry point (runForLens) with stdout captured, hands the finished page and
// the built graph to composeBrief, and prints the brief instead. --for's own stderr notices are captured and dropped: they
// describe an answer this verb does not print. Same contract as every verbs_*.h: reopens main.cpp's unnamed namespace under
// the RIPWIRE_MAIN_TU guard.

namespace
{

// Why a brief page could not be built; the caller words the refusal (its verb is in it).
enum class BriefPageFail : std::uint8_t { NoBuffer, ForFailed };

// THE brief pipeline, shared by --brief=TASK and --handoff=TASK (one post-processing path, COMPARE_LOOP_LESSONS 11-27 #9): run --for
// through its own entry point with stdout captured (cfg.forTask is the task: parseArgs set it for both verbs), compose the brief from the
// finished page and the built graph, redact it. --for's stderr notices are captured and dropped: they describe an answer neither verb prints.
// The redaction counts are left for the caller to report once, after everything it prints.
std::variant<std::string, BriefPageFail> briefPageFor( const MainDispatch& d, std::string_view task )
{
    std::string forPage;
    {
        // The buffer first, checked before --for runs: an inactive capture (no temp file, e.g. an unwritable TMPDIR) would let the whole
        // --for page reach stdout ahead of the refusal. The stderr capture comes after it, so the caller's refusal is not swallowed.
        StdoutCapture capture( true );
        if( !capture.active() )
        {
            return BriefPageFail::NoBuffer;
        }
        StderrCapture notices( true );
        const int     forRc = runForLens( d ).value_or( 1 );
        const std::optional<StdoutCaptured> page  = capture.finish();
        (void)notices.finish();
        if( !capturedWhole( page ) || forRc != 0 )
        {
            return BriefPageFail::ForFailed;
        }
        forPage = page->bytes;
    }
    std::string brief = rw::brief::composeBrief( rw::brief::BriefInputs{ .ing = d.ing, .g = d.g, .diskRoot = d.root, .task = task,
                                                                                .forPage = forPage, .budgetBytes = std::size_t( d.cfg.briefBytes ),
                                                                                .noCache = d.cfg.noCache } );
    rw::redactInPlace( brief, d.redactPtr );   // the brief quotes doc fences and manifests: same secret redaction as every body seam (--no-redact: null)
    return brief;
}

// Print the brief page for TASK — after the --handoff packet when withPacket (--handoff=TASK), alone otherwise (--brief). The brief is built
// FIRST, so a refusal prints nothing; the packet is printed exactly as a bare --handoff prints it, and the two are side by side, never
// spliced (test/handofftaskcheck.sh twin arm). Each verb keeps its own refusal words.
int answerBriefPage( const MainDispatch& d, std::string_view task, bool withPacket )
{
    if( d.multiRoot )
    {
        if( withPacket )
        {
            DISCLOSE( Diagnostics::answerRefused, "--handoff=TASK: a workspace has no single root for the packet and the brief — refused, exit 1" );
            rw::emitRaw( stderr, "ripwire: --handoff answers for ONE root (its branch/sha/diff provenance is keyed to one repo's HEAD) — run it per root\n" );
            return 1;
        }
        DISCLOSE( Diagnostics::answerRefused, "--brief: a workspace has no single root for layout, build and conventions — refused, exit 1" );
        rw::emitRaw( stderr, "ripwire: --brief answers for ONE root (its layout, build files and conventions are per repo) — run it per root\n" );
        return 1;
    }
    std::variant<std::string, BriefPageFail> page = briefPageFor( d, task );
    if( const BriefPageFail* fail = std::get_if<BriefPageFail>( &page ) )
    {
        if( withPacket )
        {
            DISCLOSE( Diagnostics::answerRefused, "--handoff=TASK: the task's brief could not be built (no buffer, or --for failed) — refused, exit 1" );
            rw::emitRaw( stderr, "ripwire: --handoff=TASK: the task's --for page could not be read whole, so no packet is printed (a bare --handoff still answers)\n" );
            return 1;
        }
        if( *fail == BriefPageFail::NoBuffer )
        {
            DISCLOSE( Diagnostics::answerRefused, "--brief: no buffer for the --for page (std::tmpfile failed) — refused before --for ran, exit 1" );
            rw::emitRaw( stderr, "ripwire: --brief: could not open a temporary buffer for the task's --for page (is TMPDIR writable?), so no brief is printed\n" );
            return 1;
        }
        DISCLOSE( Diagnostics::answerRefused, "--brief: the --for page did not buffer whole (or --for failed) — refused, exit 1" );
        rw::emitRaw( stderr, "ripwire: --brief: the task's --for page could not be read whole, so no brief is printed\n" );
        return 1;
    }
    const int rc = withPacket ? writeHandoffPacket( stdout, d.root, d.ing, d.g, d.cfg.tokenBudget ) : 0;
    const std::string& brief = std::get<std::string>( page );
    reportRedactions( stderr, d.redactCounts );
    std::fwrite( brief.data(), 1, brief.size(), stdout );
    std::fputc( '\n', stdout );
    return rc;
}

// --brief=TASK, or --handoff=TASK (HANDOFF-TASKCOND, 2026-11-27): the continuation packet exactly as --handoff prints it on this
// index, then the brief page for TASK - the slots a next session needs for its task (entries by reach, build/test commands quoted from
// manifests, act ranges, where-else, conventions), class-capped as --brief is. parseArgs refuses the two together. nullopt when neither
// asked for a brief (a bare --handoff, or RIPWIRE_HANDOFF_TASK=0, which parseArgs turned into one).
std::optional<int> runBriefPage( const MainDispatch& d )
{
    if( !d.cfg.brief.empty() )
    {
        return answerBriefPage( d, d.cfg.brief, false );
    }
    if( d.cfg.handoff && !d.cfg.handoffTask.empty() )
    {
        return answerBriefPage( d, d.cfg.handoffTask, true );
    }
    return std::nullopt;
}

}   // namespace
