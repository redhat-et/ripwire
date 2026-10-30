static int cppAnonPlainHelper() { return 0; }
namespace Anon {
struct Box { void put(); };
void Box::put() { cppAnonPlainHelper(); }
} // namespace Anon
