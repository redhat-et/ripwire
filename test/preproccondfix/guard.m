// Under the ObjC grammar `#import` parses as preproc_include (not preproc_call), so this file proves the
// descent reaches the OTHER C-family grammar too — the extractor must not be fixed for tree-sitter-cpp
// alone.

#import "objc_top.h"

#if defined( RIPWIRE_OBJC_COND )
#import "objc_guarded.h"
#endif

int objcGuardedFn( void )
{
    return 0;
}
