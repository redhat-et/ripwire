static int cppDrainHelper() { return 0; }
namespace Net {
namespace Conn {
struct Pool { void drain(); };
void Pool::drain() { cppDrainHelper(); }
} // namespace Conn
} // namespace Net
