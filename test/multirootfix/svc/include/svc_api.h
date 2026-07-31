#pragma once

// svc_api.h — the service's public API. cli/ includes THIS header by an escaping relative include
// (the DESIGN_multiRoot.md §3.1a evidence channel); the cross-root call edge into svc_handle must
// exist in the merged workspace graph (gate G-edge).
inline int svc_handle( int request )
{
    if( request < 0 )
        return -1;
    return request + 1;
}
