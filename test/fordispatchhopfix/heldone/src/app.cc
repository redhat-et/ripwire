#include "reader.h"
struct App
{
    RealReader reader_;
    RealReader* borrowed_;
    int Run();
};
int App::Run()
{
    RealReader& ref = reader_;
    const int k = ref.ReadFile( 2 );
    RealReader* ptr = borrowed_ != nullptr ? borrowed_ : &ref;
    return k + ( ptr == &ref ? 0 : 1 );
}
int UseByParam( RealReader r ) { return r.ReadFile( 1 ); }
int main()
{
    App a;
    return a.Run();
}
