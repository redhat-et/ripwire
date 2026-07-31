#include <mutex>
namespace ctx { namespace quality { std::mutex& headSnapshotIngestMutex(); } }
void f()
{
    std::lock_guard<std::mutex> ingestLk( ctx::quality::headSnapshotIngestMutex() );
}
