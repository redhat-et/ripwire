#include "disk.h"
Disk* MakeCached() { return new CachedDisk; }
