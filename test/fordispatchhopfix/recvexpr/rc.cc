struct Cch { virtual ~Cch(){} virtual int F( int k ) = 0; };
struct Lru : Cch { int F( int k ) override { return k * 3; } };
struct Arc : Cch { int F( int k ) override { return k * 4; } };
struct Dsk { int F( int k ) { return k + 1; } };
struct Hold { Cch* c_; Cch* get() { return c_; } };
struct Job { Dsk* x_; Cch* y_; Hold* hp; int Run( int k ); };
int Job::Run( int k )
{
    if( k < 0 )
    {
        return hp->get()->F( -k );
    }
    return x_->F( k ) * y_->F( k );
}
int main() { Dsk d; Lru l; Hold h{ &l }; Job j{ &d, &l, &h }; return j.Run( 1 ); }
