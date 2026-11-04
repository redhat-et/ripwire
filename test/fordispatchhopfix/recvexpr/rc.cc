struct Cch { virtual ~Cch(){} virtual int F( int k ) = 0; };
struct Lru : Cch { int F( int k ) override { return k * 3; } };
struct Arc : Cch { int F( int k ) override { return k * 4; } };
struct Dsk { int F( int k ) { return k + 1; } };
struct Hold { Cch* c_; Cch* get() { return c_; } };
struct L { Dsk* x_; Cch* y_; Hold* hp; int Load( int k ); };
int L::Load( int k ) { int a = x_->F( k ); int b = y_->F( k ); int c = hp->get()->F( k ); return a + b + c; }
int main() { Dsk d; Lru l; Hold h{ &l }; L x{ &d, &l, &h }; return x.Load( 1 ); }
