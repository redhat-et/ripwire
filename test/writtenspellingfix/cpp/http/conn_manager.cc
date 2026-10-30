#include "conn_manager.h"
namespace Envoy {
namespace Http {
static int cppStreamHelper(int h) { return h; }
void ConnectionManagerImpl::ActiveStream::decodeHeaders(int h) { cppStreamHelper(h); }
} // namespace Http
} // namespace Envoy
