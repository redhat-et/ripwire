// forpagebudgetswitch.h — the SWITCH of the `--for` page budget (SIZE-PAGE; forpages.h is the cut). Its own
// small header, as forqsitesswitch.h is for the question-sites block, because cli.h (--version's pagebudget=) decides with it and must
// not include the page emitter's dependencies.
#pragma once

#include <cstddef>
#include <string_view>

#include "infra/Diagnostics.h"  // VALIDATE — the environment is external input
#include "infra/envnumber.h"    // readEnvNumber — the one environment-number reader every knob shares

namespace rw::pagebudget
{

// THE DEFAULT CAP on everything page 1 of a PAGED default `--for` answer serves (root, rows, legend, question-sites block): TODAY'S
// page 1 — the page 1 the answer is served without the budget (full legend, the default row page) — so budget_bytes= is true of the
// page and no row main serves on page 1 leaves it; the page grows only by the cap's own digits (7500 -> 14468: +1 B). An answer
// served whole is served as main serves it (forpages.h pageAnswer, verbs_for.h serveForPage).
// MEASURED (tmp/orch-1125/size-page, DEV S1/MF1/LD/NL1/GA1, G2 grader; owner bar 11-25 = 0 items lost against main): any share below
// today drops rows main's θ5 refill serves — 95 % lost 4 items on S1+MF1 alone, 80 % 24 over DEV, a fixed 7,500 B 80 on S1.
inline constexpr std::size_t kPageCapPercent = 100;   // % of today's page 1; a cut row is on page 2 (root next=), disclosed by budget_bytes= page= withheld_bytes=

// ON by default (owner 11-25, "ON in one PR"). RIPWIRE_PAGE_BUDGET=0 turns it off: every answer is then byte-identical to the one served
// before the switch existed (test/pagebudgetcheck.sh (O)). Measurement arms: 1-100 = that percent of today's page 1; above 100 = a
// fixed cap in bytes. Any other value, or unset, is the default.
struct PageBudgetKnob
{
    bool        on      = true;
    std::size_t percent = kPageCapPercent;   // of today's page 1; 0 when off or when `bytes` is the cap
    std::size_t bytes   = 0;                    // a fixed cap (arm), 0 = none
};
[[nodiscard]] inline PageBudgetKnob pageBudgetKnob() noexcept
{
    const EnvNumber knob = readEnvNumber( "RIPWIRE_PAGE_BUDGET" );
    if( !knob.set || !VALIDATE( knob.parsed ) )   // external input: a value that is not one number is the default
    {
        return {};
    }
    if( knob.value == 0 )
    {
        return { .on = false, .percent = 0, .bytes = 0 };
    }
    if( knob.value <= 100 )
    {
        return { .on = true, .percent = static_cast<std::size_t>( knob.value ), .bytes = 0 };
    }
    return { .on = true, .percent = 0, .bytes = static_cast<std::size_t>( knob.value ) };
}
[[nodiscard]] inline bool pageBudgetOn() noexcept { return pageBudgetKnob().on; }
// The posture this process serves, as --version discloses it (pagebudget=).
[[nodiscard]] inline std::string_view defaultPageBudgetName() noexcept { return pageBudgetOn() ? "on" : "off"; }

}   // namespace rw::pagebudget
