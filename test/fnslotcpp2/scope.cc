#include "scope.h"
namespace mine {
int Server::start(int x) { return x; }
int Server::stop(int x) { return x; }
}
namespace outer { namespace inner { int Deep::run(int x) { return x; } } }
int Anon::go(int x) { return x; }
namespace c1::c2 { int Pair::f(int x) { return x; } }
namespace v0 { inline namespace v1 { int Ver::vf(int x) { return x; } } }
namespace mygrpc { int GServer::gstart(int x) { return x; } }
