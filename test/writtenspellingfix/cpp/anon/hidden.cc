static int cppAnonHiddenHelper() { return 0; }
namespace Anon {
namespace {
struct Box { void put() { cppAnonHiddenHelper(); } };
} // namespace
} // namespace Anon
