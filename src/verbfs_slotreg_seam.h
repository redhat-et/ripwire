#pragma once
// verbfs_slotreg_seam.h — the two seams through which a served --for's query-independent indexes may be answered from the
// SLOTREG record (src/verbfs_slotreg.h): the registrar index (regindex.h regIndexOf) and the header -> includers adjacency
// a header-static question walks (valuerefindex.h includersAdj). Light on purpose, as verbfs_seam.h is: regindex.h and
// valuerefindex.h include this and nothing heavier, because the record's implementation needs quality.h and warmsnap.h.
// The implementation installs itself here when the primary ingest of a cached single-root run arms VERB-FS (ingest()
// calls verbfs::slotreg::arm beside verbfs::arm); until then every pointer is null and every site builds as it always did.
//
// Installed once, on the main thread, before any verb runs; read afterwards from any thread (thread start orders it).

#include "infra/depwatch.h"   // Log / Armed — which files a build read, so a build that read one is never kept
#include "infra/emit.h"       // faultSwitchOnOnce — the mutation arms' switches

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace rw
{
struct IngestResult;
struct RegKey;
class FileAdjacency;
}

namespace rw::verbfs::slotreg
{

// The identity of an IngestResult's row arrays (files, symbols, references, bindings, includes): data pointer and size. A copy,
// a merge, an --ignore-tests filter or any other ingest has other arrays or other sizes. A template, so this header stays light.
struct ModelRows
{
    const void* rows[ 5 ]  = {};
    std::size_t sizes[ 5 ] = {};
    friend bool operator==( const ModelRows&, const ModelRows& ) = default;
};
template<class Ingest>
inline ModelRows modelRowsOf( const Ingest& ing ) noexcept
{
    return ModelRows{ { ing.files.data(), ing.symbols.data(), ing.references.data(), ing.bindings.data(), ing.includes.data() },
                      { ing.files.size(), ing.symbols.size(), ing.references.size(), ing.bindings.size(), ing.includes.size() } };
}

// What a serve attempt found, handed back to the keep call so the one stats line can say both.
struct Serve
{
    bool          served = false;
    std::uint8_t  why    = 0;   // verbfs::Why, or kWhyKey / kWhyModel below
};

struct Seams
{
    // (1) the registrar index: RegIndex::build's keys and the names whose re-export chain it cut (sorted)
    Serve ( *regServe )( const IngestResult& ing, std::vector<RegKey>& keys, std::vector<std::string>& cut ) = nullptr;
    void ( *regKeep )( const IngestResult& ing, Serve tried, const std::vector<RegKey>& keys, const std::vector<std::string>& cut, bool readsPinned ) = nullptr;
    // (2) the slot join's include adjacency: header -> the files that include it
    Serve ( *joinServe )( const IngestResult& ing, FileAdjacency& includers ) = nullptr;
    void ( *joinKeep )( const IngestResult& ing, Serve tried, const FileAdjacency& includers, bool readsPinned ) = nullptr;
    // (3) the model identity: the noted model's key when `ing` IS that model (its row arrays' data pointers and sizes), else 0.
    //     The narrow value index (valuerefindex.h narrowFor) keeps its question-independent base for the life of the process
    //     only for such a model, so an IngestResult nobody vouched for (an --ignore-tests filter, a merge) builds as before.
    std::uint64_t ( *modelKey )( const IngestResult& ing ) = nullptr;
};

inline Seams& seams() noexcept
{
    static Seams installed;
    return installed;
}

// The fault switches of the mutation arms (test/slotregcheck.sh; constexpr false under NDEBUG). ANYKEY and EMPTYREFUSED serve a
// stale or empty index ON PURPOSE, so the plain build's served-vs-fresh check stands aside for them; STALEROWS serves rows that
// differ from the model (what a pass editing the model after ingest() would leave) and is the case that check exists to catch.
struct FaultSlotRegAnyKey;
struct FaultSlotRegEmptyRefused;
struct FaultSlotRegStaleRows;
inline bool faultAnyKey() noexcept { return rw::faultSwitchOnOnce<FaultSlotRegAnyKey>( "RIPWIRE_FAULT_SLOTREG_ANYKEY" ); }
inline bool faultEmptyRefused() noexcept { return rw::faultSwitchOnOnce<FaultSlotRegEmptyRefused>( "RIPWIRE_FAULT_SLOTREG_EMPTYREFUSED" ); }
inline bool faultStaleRows() noexcept { return rw::faultSwitchOnOnce<FaultSlotRegStaleRows>( "RIPWIRE_FAULT_SLOTREG_STALEROWS" ); }
inline bool servesStaleOnPurpose() noexcept { return faultAnyKey() || faultEmptyRefused(); }
// SLOT-NARROW (test/slotbasecheck.sh V): a narrow index derived from the kept base one value short, what a base built before an
// in-place edit of the model would answer. The plain build's derived-vs-fresh check (valuerefindex.h derive) must trap it.
struct FaultSlotBaseStale;
inline bool faultBaseStale() noexcept { return rw::faultSwitchOnOnce<FaultSlotBaseStale>( "RIPWIRE_FAULT_SLOTBASE_STALE" ); }

// The files a build read, for the keep decision: the tree key pins the content of a crawled file, and nothing else. Arms the
// process-wide dependency log only when the seams are installed and no other owner holds it (none does at verb time: the
// graph's own log is disarmed before the verbs run), so an unarmed run costs nothing here. Two builds on two threads never
// share the one log: the second finds the turn taken, does not arm, and is answered without being kept.
class BuildWatch
{
public:
    explicit BuildWatch( bool wanted ) : m_turn( turn(), std::defer_lock )
    {
        m_on = wanted && m_turn.try_lock() && !depwatch::armed();
        if( m_on )
        {
            m_armed.emplace( &m_log );
        }
    }
    BuildWatch( const BuildWatch& )            = delete;
    BuildWatch& operator=( const BuildWatch& ) = delete;

    // Disarms, then: did the build read nothing but crawled files (`sortedFiles`, the index's file list)?
    bool readsPinned( const std::vector<std::string>& sortedFiles )
    {
        m_armed.reset();
        if( !m_on )
        {
            return false;
        }
        for( const depwatch::Dep& d : m_log.deps )
        {
            if( d.seam != depwatch::Seam::WholeFile || !std::binary_search( sortedFiles.begin(), sortedFiles.end(), d.path ) )
            {
                return false;   // a config read, an existence probe, or a poisoned log: the build's inputs are not all pinned
            }
        }
        return true;
    }

private:
    static std::recursive_mutex& turn() noexcept   // recursive: a build nested in another on one thread finds the log armed, never a held lock
    {
        static std::recursive_mutex one;
        return one;
    }
    std::unique_lock<std::recursive_mutex> m_turn;   // declared first: released last, after the log is disarmed
    depwatch::Log                  m_log;
    bool                           m_on = false;
    std::optional<depwatch::Armed> m_armed;
};

}   // namespace rw::verbfs::slotreg
