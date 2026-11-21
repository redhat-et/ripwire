#include "buf.h"
namespace lib
{
class Watermark : public Owned
{
public:
    void prependView( View data );
    void prependInstance( Instance& data );
    void pairBoth( View a, Instance& b );
    void shadowed( View data );
};

// POSITIVE: the argument's declared type is exactly one overload's parameter type
void Watermark::prependView( View data ) { Owned::prepend( data ); }
void Watermark::prependInstance( Instance& data ) { Owned::prepend( data ); }
void Watermark::pairBoth( View a, Instance& b ) { Owned::pair( a, b ); }

View makeView( int k );
Instance& otherInstance();

// NEGATIVE: the parameter is hidden by a block-scope reference of the other type (only the innermost declaration counts)
void Watermark::shadowed( View data )
{
    {
        Instance& data = otherInstance();
        Owned::prepend( data );
    }
}

// NEGATIVE: an argument that is not a declared name (a call) keeps the split
void unknownArg( Owned& o, int k ) { o.prepend( makeView( k ) ); }
// NEGATIVE: a derived-class argument both overloads accept (derived-to-base) keeps the split
void derivedArg( Owned& o, Derived& d ) { o.put( d ); }
// NEGATIVE: a template overload in the set keeps the split
void templateArg( Owned& o, View v ) { o.push( v ); }
// NEGATIVE: a user conversion (Conv -> View) keeps the split
void convArg( Owned& o, Conv c ) { o.take( c ); }
// NEGATIVE: a pointer argument is not the reference overload's exact type (Instance* -> Base* is the target)
void ptrArg( Owned& o, Instance* p ) { o.ptr( p ); }
// NEGATIVE: a const argument cannot bind the non-const reference overload
void constArg( Owned& o, const Instance& ci ) { o.cref( ci ); }
}

namespace far
{
class View { public: operator lib::View() const; };
// NEGATIVE: the same unqualified spelling in another namespace names another type (far::View converts to lib::View)
void farCaller( lib::Owned& o, View v ) { o.prepend( v ); }
}

namespace lib
{
// NEGATIVE (receiver): a qualified call naming a class outside the tree, made from inside a namesake overload set (envoy's
// `Buffer::set( std::string_view data ) { proxy_wasm::BufferBase::set( data ); }`): the tier is not the set the call names
class Wrapped : public ext::Base
{
public:
    void wrap( View data ) { ext::Base::wrap( data ); }
    void wrap( Instance& data ) { ext::Base::wrap( data ); }
};
// NEGATIVE (receiver): a NAME-ONLY call through a field of a type outside the tree (envoy's FailingSignUtility forwarding to
// `real_.getSha256Digest( buffer )`): no lookup tied the namesake overloads to the receiver
class Relay
{
public:
    void relay( View data ) { real_.relay( data ); }
    void relay( Instance& data ) { real_.relay( data ); }

private:
    ext::Real real_;
};
}

namespace lib
{
// POSITIVE: Box<const View>& is exactly hold( Box<const View>& )'s type; Box<View> by value is another type (the inner const is
// the type's, not the parameter's)
void innerConstArg( Holder& h, Box<const View>& b ) { h.hold( b ); }
// POSITIVE: `const Box<View*>&` and `Box<View*> const&` are one type: the `*` inside <...> is not the parameter's own pointer
// (CR #716; split before: the nested `*` chose the pointer branch, which kept the leading const in the core)
void ptrInTemplateArg( Holder& h, const Box<View*>& b ) { h.wrapPtr( b ); }
}
