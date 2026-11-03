static int cppRealFlushHelper() { return 0; }
namespace Envoy {
namespace Stats {
SOME_REGISTRATION(sink);
void Sink::flush() { cppRealFlushHelper(); }
} // namespace Stats
} // namespace Envoy
