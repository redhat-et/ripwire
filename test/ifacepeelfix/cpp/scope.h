#include <memory>
// fix round 1 (B1): a member written as an alias peels only when the alias is IN SCOPE where the member is written
namespace sc {
class Spin { public: virtual ~Spin() = default; virtual int spin(int x) = 0; };
class SpinA : public Spin { public: int spin(int x) override { return x; } };
class SpinB : public Spin { public: int spin(int x) override { return x + 1; } };
using SpinPtr = std::shared_ptr<Spin>;
class Motor { public: int turn(int x) { return x; } };
using MotorPtr = std::unique_ptr<Motor>;
class SameNs { public: int go(int x) { return s_->spin(x); } SpinPtr s_; };
namespace inner { class InnerNs { public: int go(int x) { return s_->spin(x); } SpinPtr s_; }; }
// a template parameter named like the alias in the SAME namespace
template <class SpinPtr> class TmplSame { public: int go(int x) { return s_->spin(x); } SpinPtr s_; };
}
class Wheel { public: int turn(int x) { return x; } };   // a namesake of Motor::turn
class GlobalQ { public: int go(int x) { return s_->spin(x); } sc::SpinPtr s_; };
// a template parameter named like an alias of another namespace
template <class SpinPtr> class TmplIface { public: int go(int x) { return s_->spin(x); } SpinPtr s_; };
template <class MotorPtr> class TmplConc { public: int go(int x) { return m_->turn(x); } MotorPtr m_; };
// the alias is not visible here: another namespace, a wrong qualifier
namespace other { class NotInScope { public: int go(int x) { return s_->spin(x); } SpinPtr s_; }; }
namespace other { class WrongQual { public: int go(int x) { return s_->spin(x); } zz::SpinPtr s_; }; }
// an EXTERNAL name brought in by a using-declaration
namespace ext { using extlib::SpinPtr; class ExtUser { public: int go(int x) { return s_->spin(x); } SpinPtr s_; }; }
// a using-directive brings the alias into scope
namespace ud { using namespace sc; class ViaDirective { public: int go(int x) { return s_->spin(x); } SpinPtr s_; }; }
// class-scoped aliases of one name: each member reads its OWN class's
class KxI { public: virtual ~KxI() = default; virtual int kick(int x) = 0; };
class KxI1 : public KxI { public: int kick(int x) override { return x; } };
class KxI2 : public KxI { public: int kick(int x) override { return x + 1; } };
class KyC { public: int kick(int x) { return x; } };
struct HoldX { using Ptr = std::shared_ptr<KxI>; int goX(int x) { return p_->kick(x); } Ptr p_; };
struct HoldY { using Ptr = std::unique_ptr<KyC>; int goY(int x) { return p_->kick(x); } Ptr p_; };
