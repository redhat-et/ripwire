static int cppWrongFlushHelper() { return 0; }
namespace Envoy {
namespace Upstream2 {
namespace Stats {
void Sink::flush() { cppWrongFlushHelper(); }
} // namespace Stats
} // namespace Upstream2
} // namespace Envoy
