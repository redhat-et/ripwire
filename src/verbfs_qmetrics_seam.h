#pragma once
// verbfs_qmetrics_seam.h — the seam through which computeQMetrics and computeImpure (graph.h) may be answered from the
// VERB-FS QMETRICS record (src/verbfs_qmetrics.h). Light on purpose: graph.h includes this and nothing heavier, because the
// record's implementation needs verbfs.h, which needs quality.h, which includes graph.h. verbfs::armQMetrics installs it
// for the primary ingest of a cached single-root run, right after verbfs::arm and only where that armed (ingest.cpp); until
// then both pointers are null and both functions compute exactly as they always did.
//
// Installed once, on the main thread, before any verb runs; read afterwards from any thread (thread start orders it).

#include <vector>

namespace rw
{
struct IngestResult;
struct Graph;
struct QMetrics;
}

namespace rw::verbfs
{

// Each answers what its graph.h namesake computes for ( ing, g ): from the record when its key proves the stored answer is the
// one the computation would produce, else by running the computation (and offering the result to the record).
struct DerivedSeams
{
    QMetrics ( *qmetrics )( const IngestResult& ing, const Graph& g )        = nullptr;
    std::vector<char> ( *impure )( const IngestResult& ing, const Graph& g ) = nullptr;
};

inline DerivedSeams& derivedSeams() noexcept
{
    static DerivedSeams installed;
    return installed;
}

// The one dispatch both graph.h functions make: the installed seam's answer, else the computation itself.
template <class Answer>
inline Answer servedOrComputed( Answer ( *served )( const IngestResult&, const Graph& ), Answer ( *computed )( const IngestResult&, const Graph& ), const IngestResult& ing,
                                const Graph& g )
{
    return served != nullptr ? served( ing, g ) : computed( ing, g );
}

}   // namespace rw::verbfs
