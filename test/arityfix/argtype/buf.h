// B2.3 argument-type fixture: one class's same-arity overloads, and callers whose argument's declared type picks one.
namespace lib
{
class View { public: const char* p; };
class Base { };
class Instance : public Base { };
class Other { };
class Derived : public Base, public Other { };
class Conv { public: operator View() const; };

class Owned
{
public:
    void prepend( View data );
    void prepend( Instance& data );
    void put( Base& b );
    void put( Other& o );
    void take( View v );
    void take( Other o );
    template <class T> void push( T t );
    void push( View v );
    void ptr( Instance& i );
    void ptr( Base* b );
    void cref( Instance& i );
    void cref( Other o );
    void pair( Instance& a, View b );
    void pair( View a, Instance& b );
};
}

// CR #705 (argtypepick): a const INSIDE a template argument list is part of the type, never the parameter's own const
namespace lib
{
template <class T> class Box { public: T value; };
class Holder
{
public:
    void hold( Box<View> b );
    void hold( Box<const View>& b );
    void wrapPtr( Box<View*> const& b );
    void wrapPtr( Box<View>& b );
};
}
