#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_brief.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

#include "brief.h"        // rw::brief::composeBrief — the eight sections and the size fit (shared with the MCP `brief` verb)
#include "infra/emit.h"   // rw::emitRaw
#include <string_view>

// verbs_brief.h — the CLI `--brief="TASK"` handler. parseArgs set forTask to the brief's task, so the run was prepared as a
// --for run; this handler runs --for through its own entry point (runForLens) with stdout captured, hands the finished page and
// the built graph to composeBrief, and prints the brief instead. --for's own stderr notices are captured and dropped: they
// describe an answer this verb does not print. Same contract as every verbs_*.h: reopens main.cpp's unnamed namespace under
// the RIPWIRE_MAIN_TU guard.

namespace
{

// The brief, or nullopt when --brief was not asked.
std::optional<int> runBrief( const MainDispatch& d )
{
    if( d.cfg.brief.empty() )
    {
        return std::nullopt;
    }
    if( d.multiRoot )
    {
        DISCLOSE( Diagnostics::answerRefused, "--brief: a workspace has no single root for layout, build and conventions — refused, exit 1" );
        rw::emitRaw( stderr, "ripwire: --brief answers for ONE root (its layout, build files and conventions are per repo) — run it per root\n" );
        return 1;
    }
    std::string forPage;
    {
        // The buffer first, checked before --for runs: an inactive capture (no temp file, e.g. an unwritable TMPDIR) would let the whole
        // --for page reach stdout ahead of the refusal. The stderr capture comes after it, so this refusal is not swallowed.
        StdoutCapture capture( true );
        if( !capture.active() )
        {
            DISCLOSE( Diagnostics::answerRefused, "--brief: no buffer for the --for page (std::tmpfile failed) — refused before --for ran, exit 1" );
            rw::emitRaw( stderr, "ripwire: --brief: could not open a temporary buffer for the task's --for page (is TMPDIR writable?), so no brief is printed\n" );
            return 1;
        }
        StderrCapture notices( true );
        const int     forRc = runForLens( d ).value_or( 1 );
        const std::optional<StdoutCaptured> page  = capture.finish();
        (void)notices.finish();
        if( !capturedWhole( page ) || forRc != 0 )
        {
            DISCLOSE( Diagnostics::answerRefused, "--brief: the --for page did not buffer whole (or --for failed) — refused, exit 1" );
            rw::emitRaw( stderr, "ripwire: --brief: the task's --for page could not be read whole, so no brief is printed\n" );
            return 1;
        }
        forPage = page->bytes;
    }
    const std::string brief = rw::brief::composeBrief( rw::brief::BriefInputs{ .ing = d.ing, .g = d.g, .diskRoot = d.root, .task = d.cfg.brief,
                                                                                .forPage = forPage, .budgetBytes = std::size_t( d.cfg.briefBytes ) } );
    std::fwrite( brief.data(), 1, brief.size(), stdout );
    std::fputc( '\n', stdout );
    return 0;
}

}   // namespace
