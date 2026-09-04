// Phase 5 fixture — the declaration half of `clamp` (gate arm G): a name in the C++ table (`std::clamp`,
// <algorithm>) DECLARED here and defined in decl.cpp. ext.cpp includes this header, so the include-resolved
// declaration is evidence for its bare `clamp( 1 )` call and the edge to decl.cpp::clamp stays.
#pragma once

int clamp( int v );
