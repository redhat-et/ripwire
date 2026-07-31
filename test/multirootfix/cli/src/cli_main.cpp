// cli_main.cpp — the client. The escaping relative include below is the §3.1a cross-root evidence:
// lexically it leaves cli/ and lands exactly on the sibling checkout svc/'s header, so the merged
// workspace resolves svc_handle to svc's def (gate G-edge). same_name_helper is the G-forbid probe:
// its ONLY evidence-free candidates are cli's own (cli_helper.cpp) and svc's decoy — the resolver must
// stay inside this root.
#include "../../svc/include/svc_api.h"

int same_name_helper();   // cli's own helper (defined in cli_helper.cpp)

int run_cli( int request )
{
    return svc_handle( request ) + same_name_helper();
}
