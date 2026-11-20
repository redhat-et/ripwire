#include "buf.h"
namespace lib
{
void Owned::prepend( View data ) { (void)data; }
void Owned::prepend( Instance& data ) { (void)data; }
void Owned::put( Base& b ) { (void)b; }
void Owned::put( Other& o ) { (void)o; }
void Owned::take( View v ) { (void)v; }
void Owned::take( Other o ) { (void)o; }
template <class T> void Owned::push( T t ) { (void)t; }
void Owned::push( View v ) { (void)v; }
void Owned::ptr( Instance& i ) { (void)i; }
void Owned::ptr( Base* b ) { (void)b; }
void Owned::cref( Instance& i ) { (void)i; }
void Owned::cref( Other o ) { (void)o; }
void Owned::pair( Instance& a, View b ) { (void)a; (void)b; }
void Owned::pair( View a, Instance& b ) { (void)a; (void)b; }
}
namespace lib
{
void Holder::hold( Box<View> b ) { (void)b; }
void Holder::hold( Box<const View>& b ) { (void)b; }
}
