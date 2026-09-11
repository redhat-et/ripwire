#pragma once
// tablelookup.h — find a row in a small constexpr table by one of its string fields.
//
// WHY THIS EXISTS. Two independent layers grew the identical function: `lookupLang` (ingest, maps a
// file extension to a language row) and `agentTarget` (wrap, maps an agent name to its target row).
// Both are a linear scan over a constexpr array comparing one std::string_view member, returning a
// pointer or nullptr. `--quality-delta` flagged the second as a clone of the first and refused the
// change, which was correct.
//
// It lives in infra/ rather than in either caller because the alternative was worse: wrap.h and
// ingest_crawl.h share no header, so deduplicating in place would have coupled the CLI's agent table
// to the ingest hot path (lookupLang has ~21 call sites across six ingest translation units) purely to
// satisfy a lint. infra/ is below both and depends on neither, so nothing is coupled to anything.
//
// LINEAR, deliberately. These tables are ~8 and ~40 rows; a linear scan over contiguous constexpr
// storage beats any lookup structure at this size and keeps the call constant-foldable. Do not
// "optimize" this into a hash without a measurement showing one of these tables grew enough to matter.

#include <cstddef>
#include <string_view>

namespace rw
{

// Row is deduced from the MEMBER POINTER, not from the container, so this binds to a C array and to a
// std::array alike — the two callers happen to use one of each (wrap's kAgentTargets is a plain array,
// ingest's kLangTable is a std::array<LangEntry, 46>).
// The KEY type is deduced too, not fixed to string_view: the third caller (lanes.h::findClaimByKey)
// matches a std::uint64_t. --quality-delta found that one — it flagged this helper as a clone of it,
// which is how a two-instance dedup turned out to be a three-instance one.
template< typename Table, typename Row, typename Key, typename Wanted >
constexpr const Row* findByField( const Table& rows, Key Row::*field, const Wanted& wanted ) noexcept
{
    for( const Row& r : rows )
    {
        if( r.*field == wanted )
        {
            return &r;
        }
    }
    return nullptr;
}

}   // namespace rw
