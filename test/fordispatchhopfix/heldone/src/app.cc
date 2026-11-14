#include "reader.h"
struct App
{
    RealReader reader_;
    RealReader* borrowed_;
    int Run();
};
int App::Run()
{
    RealReader* ptr = &reader_;
    RealReader& ref = reader_;
    return ptr != nullptr && &ref == ptr ? 0 : 1;
}
int UseByParam( RealReader r ) { return r.ReadFile( 1 ); }
int main()
{
    App a;
    return a.Run();
}
