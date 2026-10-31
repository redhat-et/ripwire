#include "filter.h"
namespace Http { int BufferFilter::decodeHeaders(int h) { return h; } }
namespace Router { int Filter::decodeHeaders(int h) { return h + 1; } }
