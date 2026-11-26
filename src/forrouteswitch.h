// forrouteswitch.h — the SWITCH of the ROUTING lane's two defaults (11-25): the file-gap ground of `--for`'s confidence= (lexical.h
// deriveForConfidence) and the edit-file body form on an edit task (forbodiesform.h bodyEditFormOn, lane θ17). Its own small header,
// as fortinyshapeswitch.h is for the tiny shape, because lexical.h and forbodiesform.h both decide with it and neither may include
// the other.
#pragma once

#include "infra/envnumber.h"   // readEnvNumber — the one environment-number reader every knob shares

namespace rw::routing
{

// ON by default (owner 11-25 "ON in one PR"). RIPWIRE_ROUTING=0 turns both defaults off: every answer is then byte-identical to the
// one served before this switch existed (test/routingcheck.sh (O)). Any other value, or unset, leaves them on.
[[nodiscard]] inline bool routingOn() noexcept
{
    const EnvNumber knob = readEnvNumber( "RIPWIRE_ROUTING" );
    return !( knob.parsed && knob.value == 0 );
}

}   // namespace rw::routing
