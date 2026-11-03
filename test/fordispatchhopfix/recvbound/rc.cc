struct Src { virtual ~Src(){} virtual int F( int k ) = 0; };
struct Dsk : Src { int F( int k ) override { return k + 1; } };
struct Net : Src { int F( int k ) override { return k + 2; } };
#include "cch.h"
struct Lru : Cch { int F( int k ) override { return k * 3; } };
struct Hold { Cch* c_; Cch& get() { return *c_; } };
struct L { Src* x_; Cch* y_; Hold h; int Load( int k ); };
int L::Load( int k ) { int a = this->x_->F( k ); int b = y_->F( k ); int c = h.get().F( k ); return a + b + c; }
int main() { Dsk d; Net n; Lru l; L x{ &d, &l, { &l } }; return x.Load( 1 ); }
