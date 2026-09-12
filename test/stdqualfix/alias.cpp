// test/stdqualfix — file 11: the NON-std control, and the reason the guard is std-only. `fs` is a namespace
// ALIAS, so the written qualifier ("fs") never equals the def's scope ("fsimpl"): the canonical tier misses
// and the bare-name spray lands on the lone `exists` — which here is the TRUE target. A general "qualifier
// must name the scope" rule would delete this edge; the std:: guard must leave it alone.

namespace vendor
{
namespace fsimpl
{
bool exists( const char* path ) { return path != nullptr; }
}
}

namespace fs = vendor::fsimpl;

bool probePath( const char* path )
{
    return fs::exists( path );
}
