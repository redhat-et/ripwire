// fix round 2 (D1): "the class is an interface" must not count a constructor, a destructor or a member defined out of line.
#include <memory>
namespace d1 {
class BaseOol { public: virtual ~BaseOol(); virtual int act( int x ); };            // concrete: bodies in scope3.cc
class OolA : public BaseOol { public: int act( int x ) override; };
class OolB : public d1::BaseOol { public: int act( int x ) override; };
using BaseOolPtr = std::shared_ptr<BaseOol>;
class UsesOol { public: int go( int x ); BaseOolPtr b_; };

class BaseCtor { public: BaseCtor(); virtual ~BaseCtor() = default; virtual int act( int x ) { return x; } };   // concrete: a declared ctor only
class CtorA : public BaseCtor { public: int act( int x ) override { return x + 1; } };
class CtorB : public BaseCtor { public: int act( int x ) override { return x + 2; } };
using BaseCtorPtr = std::shared_ptr<BaseCtor>;
class UsesCtor { public: int go( int x ) { return b_->act( x ); } BaseCtorPtr b_; };

class BaseDtor { public: virtual ~BaseDtor(); virtual int act( int x ) { return x; } };   // concrete: a declared dtor only (never defined here)
class DtorA : public BaseDtor { public: int act( int x ) override { return x + 1; } };
class DtorB : public BaseDtor { public: int act( int x ) override { return x + 2; } };
using BaseDtorPtr = std::shared_ptr<BaseDtor>;
class UsesDtor { public: int go( int x ) { return b_->act( x ); } BaseDtorPtr b_; };

class PureI { public: virtual ~PureI() = default; virtual int act( int x ) = 0; };   // a real interface
class PureA : public PureI { public: int act( int x ) override { return x + 1; } };
class PureB : public PureI { public: int act( int x ) override { return x + 2; } };
using PurePtr = std::shared_ptr<PureI>;
class UsesPure { public: int go( int x ) { return b_->act( x ); } PurePtr b_; };
}
