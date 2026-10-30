// FN-SLOT S2 fix 1 fixture (E* arms): the in-tree classes and the namespaces they sit in.
namespace mine {
struct Server { int start(int x); int stop(int x); int both(int k); };
}
namespace outer { namespace inner { struct Deep { int run(int x); }; } }
namespace { struct Anon { int go(int x); }; }
namespace c1::c2 { struct Pair { int f(int x); }; }
namespace v0 { inline namespace v1 { struct Ver { int vf(int x); }; } }
namespace mygrpc { struct GServer { int gstart(int x); }; }   // E1f: a namesake namespace that only ENDS with the qualifier's text (`grpc`) on no :: boundary
