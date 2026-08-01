#include <mutex>
namespace rw { namespace quality { std::mutex& headSnapshotIngestMutex(); } }
void f()
{
    std::lock_guard<std::mutex> ingestLk( rw::quality::headSnapshotIngestMutex() );
}
