// forqsitesswitch.h — the SWITCH of the `--for` question-sites block (θ11; forqsites.h is the block). Its own small header, as
// foractlineswitch.h is for the act line, because cli.h (--version's qsites=) decides with it and must not include the block's
// dependencies (search.h, ingest.h, ...).
#pragma once

#include <string_view>

#include "infra/envnumber.h"   // readEnvNumber — the one environment-number reader every knob shares

namespace rw::qsites
{

// ON by default (owner decision 11-24; lane THETA11-FLIP, measured offline on S1, MF1, LD, NL1, NL1H, NL2, NL3).
// RIPWIRE_THETA11=0 turns it off: every answer is then byte-identical to the one served before the block existed
// (test/forqsitescheck.sh (Q5)(I)). Any other value, or unset, leaves it on; the shared knob reader decides what "0" is.
[[nodiscard]] inline bool thetaElevenOn() noexcept
{
    const EnvNumber knob = readEnvNumber( "RIPWIRE_THETA11" );
    return !knob.parsed || knob.value != 0;
}
// The posture this process serves, as --version discloses it (qsites=).
[[nodiscard]] inline std::string_view defaultQsitesName() noexcept { return thetaElevenOn() ? "on" : "off"; }

}   // namespace rw::qsites
