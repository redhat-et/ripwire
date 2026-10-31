// train 42b CodeRabbit harvest (review 5712563408): two alias spellings that must NOT peel to the pointee.
#include <memory>
namespace crh {
class RunI { public: virtual ~RunI() = default; virtual int run( int x ) = 0; virtual int peek() = 0; };
class RunA : public RunI { public: int run( int x ) override { return x + 1; } int peek() override { return 1; } };
class RunB : public RunI { public: int run( int x ) override { return x + 2; } int peek() override { return 2; } };
using RunPtr = std::shared_ptr<RunI>;
class Ctl { public: int go( int x ) { return r_->run( x ); } RunPtr r_; };            // control: the alias member peels (iface row)
class PtrUser { public: int go() { return p_->peek(); } RunPtr* p_; };                // a POINTER to the alias: `p_->` is the smart pointer's own

class Gadget { public: virtual ~Gadget() = default; virtual int spin() = 0; };
class GadgetA : public Gadget { public: int spin() override { return 1; } };
class GadgetB : public Gadget { public: int spin() override { return 2; } };
template <class Gadget> class TplHolder { public: using GPtr = std::shared_ptr<Gadget>; int go() { return g_->spin(); } GPtr g_; };   // Gadget is the PARAMETER
}
