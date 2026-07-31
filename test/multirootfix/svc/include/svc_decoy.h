#pragma once

// svc_decoy.h — the G-forbid decoy: svc's OWN same_name_helper. cli/ defines a same-named helper in its
// own tree and calls it bare; with NO include evidence reaching this file, the merged graph must NEVER
// form a cross-root edge here (name-based resolution never crosses roots). The mutation check points
// cli's include AT this file, and only then must the edge flip to it (evidence-driven, not name-driven).
inline int same_name_helper()
{
    return 41;
}
