// consumer.cpp — includes ONLY dirA/x.h by PATH (a quote include, resolved relative-to-includer).
// The old basename `--deps` resolver matched the bare basename `x.h` and linked BOTH dirA/x.h and
// dirB/x.h (or the wrong one). The precise resolver must show an edge to dirA/x.h ONLY.
#include "dirA/x.h"
// An ANGLE include of an in-repo file: angle form is external/unresolvable without a build system, so it
// must contribute NO file->file edge (never basename-matched to dirB/x.h).
#include <dirB/x.h>
int consume( void ) { return alpha(); }
