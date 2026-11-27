// #446 fixture: C++ base-clause shapes the @reference.base capture must read
// (test/chacheck.sh arm CPP-BASE-CAP). Byte-identical to main on every case.

struct Base { virtual void f(); };

// Direct, qualified and multiple inheritance
class Dog : public Base { public: void f() override; };
class Cat : private Base {};
class Multi : public Dog, private Cat {};

// Template bases (the CRTP family — the capture must reach the inner type_identifier)
template <class T> struct TBase { void g(); };
struct Tmpl  : TBase<int> {};                        // unqualified template base
struct QualTmpl : ns::TBase<int> {};                 // qualified (ns declared below)
struct Crtpd : Crtp<Crtpd> {};                       // CRTP
class Multi2 : public Base, protected virtual TBase<long> {};
template <class T> struct DepT : TBase<T> {};        // dependent
struct Outer { template <class T> struct In : TBase<T> {}; };  // in-class template

// Near-misses: these must NOT produce a base ref
struct : Base { int x; } anon_var;                   // nameless struct: no def, no edge
// (a template SPECIALIZATION keeps its single walk under captureSpecializationHeader)
template <> struct Tmpl<void> : Base {};             // specialization: one walk, not two

namespace ns { template <class T> struct TBase { void g(); }; }
template <class D> struct Crtp { void run(); };
