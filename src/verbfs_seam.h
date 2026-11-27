#pragma once
// verbfs_seam.h — the three seams through which a verb's file-system pass may be answered from the VERB-FS record
// (src/verbfs.h). Light on purpose: search.h, clones.h and formanifest.h include this and nothing heavier, because
// clones.h sits inside quality.h's include closure and the record's implementation needs quality.h (the cache-dir
// ladder) and warmsnap.h (the stat signature). The implementation installs itself here when the primary ingest of a
// cached single-root run arms it (verbfs::arm, called from ingest()); until then every pointer is null and every
// site takes the path it always took, byte for byte and syscall for syscall.
//
// Installed once, on the main thread, before any verb runs; read afterwards from any thread (thread start orders it).

#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
struct IngestResult;
struct CloneGroup;
}

namespace rw::verbfs
{

// ── (1) the literal scan ──────────────────────────────────────────────────────────────────────────────────────────
// One scan's pre-filter. `skip( f )` is true only when no pattern of the scan can occur in file f AND f is still the
// file its filter was built from; the scan then neither opens nor reads it. `noteRead` sees every file the scan did
// read (its bytes, or nullopt when the read failed) so a file without a usable filter gets one. `finish` runs after
// the scan's workers joined: the stats line, and the record write when enough was learned. Called from the scan
// workers: `skip` and `noteRead` touch only file f's slots and shared atomics.
class GrepSieve
{
public:
    virtual ~GrepSieve() = default;
    virtual bool skip( std::uint32_t fileId ) noexcept = 0;
    virtual void noteRead( std::uint32_t fileId, const std::optional<std::string>& bytes ) noexcept = 0;
    virtual void finish() noexcept = 0;
};

// ── (2) the exact clone pass ─────────────────────────────────────────────────────────────────────────────────────
// `serve` answers a findClones( ing, minTokens ) whose every model input digests to `inputDigest` from the stored
// groups, when every file the stored computation read still carries the signature it had; `startNs` (out) is the
// clock reading the computation's settle rule is measured from. `keep` offers the groups a computation produced and
// the files it read (ascending, unique), to be stored once those files' signatures are settled.
struct CloneServe
{
    bool      served  = false;
    long long startNs = 0;
};

// ── (3) the manifest probe ───────────────────────────────────────────────────────────────────────────────────────
// The kind of `<rootPrefix><dir>/<name>` as the manifest probe reads it. `Live`: probe it now (a symbolic link is
// always Live — its target can change without its directory noticing).
enum class EntryKind : std::uint8_t
{
    NotRegular,   // absent, a directory, or anything else that is not a regular file and not a link
    Regular,
    Live,
};

struct Seams
{
    std::unique_ptr<GrepSieve> ( *grepSieve )( const IngestResult& ing, std::span<const std::string> pats, bool regex, bool noPrefilter ) = nullptr;
    CloneServe ( *cloneServe )( const IngestResult& ing, int minTokens, std::uint64_t inputDigest, std::vector<CloneGroup>& out ) = nullptr;
    void ( *cloneKeep )( const IngestResult& ing, int minTokens, std::uint64_t inputDigest, const std::vector<CloneGroup>& groups,
                         std::span<const std::uint32_t> readFileIds, long long startNs ) = nullptr;
    // one kind per ( dir, name ), dir-major; empty: probe every name live
    std::vector<EntryKind> ( *entryKinds )( const IngestResult& ing, std::string_view rootPrefix, std::span<const std::string_view> dirs,
                                            std::span<const std::string_view> names ) = nullptr;
};

inline Seams& seams() noexcept
{
    static Seams installed;
    return installed;
}

}   // namespace rw::verbfs
