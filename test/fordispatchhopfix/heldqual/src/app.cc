#include "reader.h"
struct Other
{
    b::Reader other_;
};
namespace b
{
struct Sink
{
    Reader plain_;
};
}   // namespace b
struct App
{
    a::Reader mine_;
    int Run();
};
int App::Run() { return mine_.ReadFile( 1 ); }
