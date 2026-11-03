#include "source.h"
int RunAll( bool remote )
{
    DiskSource disk;
    NetSource net;
    Source* s = remote ? static_cast<Source*>( &net ) : static_cast<Source*>( &disk );
    return s != nullptr ? 0 : 1;
}
int main() { return RunAll( false ); }
