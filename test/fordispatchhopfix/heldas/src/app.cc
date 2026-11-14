#include "reader.h"
struct App
{
    RealReader reader_;
    RealReader* borrowed_;
    int Run();
};
int App::Run()
{
    RealReader scratch;
    RealReader* ptr = &scratch;
    RealReader& ref = scratch;
    RealReader extra;
    return ptr != nullptr && &ref != &extra ? 0 : 1;
}
int UseByParam( RealReader r ) { return r.ReadFile( 1 ); }
int main()
{
    App a;
    return a.Run();
}
