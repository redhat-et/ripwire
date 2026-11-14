#include "reader.h"
struct App
{
    LongReader reader_;   // the reader this app owns, built with it; the fixture key below crosses the 160-byte cut of a held row: .............api_key = 0123456789abcdef0123456789abcdef0123456789abcdef
    int Run();
};
int App::Run() { return reader_.ReadFile( 1 ); }
