// galleryHost.cpp — the CPU half of the dual-compile pair. It calls the SAME ml_styleFor the shader
// calls, so --callers=ml_styleFor must name a caller from each side (that cross-half reachability is
// the whole point of indexing shaders).
#include "AAPLSharedTypes.h"

float galleryHostCoverage( unsigned int personality )
{
    const MlStyle s = ml_styleFor( personality );
    return s.coverage;
}

float galleryHostWarmth( unsigned int personality )
{
    const MlStyle s = ml_styleFor( personality );
    return s.warmth;
}
