static int cppSoloHelper() { return 0; }
namespace Solo {
namespace {
struct Pad { void put() { cppSoloHelper(); } };
} // namespace
} // namespace Solo
namespace Plain {
struct Pad { void put() { cppSoloHelper(); } };
} // namespace Plain
