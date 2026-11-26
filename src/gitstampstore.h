#pragma once

// gitstampstore.h — C1-STAMP: the process-wide answer table behind the six small git questions a served --for asks.
//
// WHAT IT IS. A served warm --for started seven git children (A1 warm profile, 2026-11-25, main fec2ab27c): the history
// walk's freshness key asked `rev-parse --verify HEAD`, `log -1 --format=%ct HEAD` and `log --since=@<epoch> … --format=%H`,
// the path offset asked `rev-parse --show-toplevel`, and the at= stamp asked `rev-parse --verify HEAD` again, `status
// --porcelain` and `rev-parse --is-shallow-repository`. Six of them answer from a handful of small files under .git and
// take 0.3–1.3 ms of git each, plus ~7.5 ms of shell and process start. This table holds those six answers for ONE root,
// loaded from a STAMP record that gitstampcache.h has already checked against every file the answers depend on, and
// collects the answers a run had to ask git for, so gitstampcache.h can record them for the next run.
//
// WHAT IT IS NOT. `git status` (the +dirty bit) is never stored here: it is recomputed on every call (gitstamp.h starts
// it early instead). Nothing is served unless gitstampcache.h armed the table for this process, and it arms it only on a
// one-shot CLI --for over one git root; every other verb, the MCP and LSP servers and every other root see an empty,
// unarmed table and run git exactly as before.
//
// THE KEY IS THE COMMAND LINE. An entry is found by the exact command string the uncached path would have handed to
// popen — the hardened prefix, every filter pin, the root's spelling, the window's resolved --since and the walk budget
// included — so a run that would have asked anything different misses and asks git. The caller also names the directory
// the question is about, and only the armed root (in either of its two spellings) is ever looked up or recorded: the
// record's dependencies are the root's, and they say nothing about a nested repository below it.
//
// Lower header on purpose: gitmine.h and quality.h consult it from their git readers, and it depends on nothing of theirs.

#include "infra/tablelookup.h"   // findByField — the one row-by-field scan

#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::gitstampstore
{

// One git answer, as the reader that asked it saw it: the exit status and the output lines.
struct Answer
{
    std::string              cmd;
    int                      status = 0;
    std::vector<std::string> lines;
};

struct Table
{
    std::mutex          lock;
    std::string         root;       // the root as the command line spelled it; "" = not armed
    std::string         rootReal;   // its realpath (gitRepoToplevel is asked with a realpath'd directory)
    std::vector<Answer> served;     // the validated record's answers
    std::vector<Answer> offered;    // answers this run asked git for, to record
};

inline Table& table()
{
    static Table t;
    return t;
}

namespace detail
{
inline bool isArmedRoot( const Table& t, std::string_view dir ) noexcept
{
    return !t.root.empty() && ( dir == t.root || dir == t.rootReal );
}

inline const Answer* find( const std::vector<Answer>& answers, std::string_view cmd ) noexcept
{
    return findByField( answers, &Answer::cmd, cmd );
}
}   // namespace detail

// The stored answer to `cmd` about `dir`, or nullopt: then the caller runs git, exactly as without a record.
inline std::optional<Answer> lookup( std::string_view dir, std::string_view cmd )
{
    Table&                            t = table();
    const std::lock_guard<std::mutex> guard( t.lock );
    if( !detail::isArmedRoot( t, dir ) )
    {
        return std::nullopt;
    }
    const Answer* hit = detail::find( t.served, cmd );
    if( hit == nullptr )
    {
        hit = detail::find( t.offered, cmd );
    }
    return hit != nullptr ? std::optional<Answer>( *hit ) : std::nullopt;
}

// Hand over an answer git just gave. The caller decides `isRecordable`: only a well-formed success is ever stored, so a
// failure or a timeout is asked again next run, exactly as today.
inline void offer( std::string_view dir, std::string_view cmd, bool isRecordable, int status, const std::vector<std::string>& lines )
{
    if( !isRecordable )
    {
        return;
    }
    Table&                            t = table();
    const std::lock_guard<std::mutex> guard( t.lock );
    if( !detail::isArmedRoot( t, dir ) || detail::find( t.served, cmd ) != nullptr || detail::find( t.offered, cmd ) != nullptr )
    {
        return;
    }
    t.offered.push_back( Answer{ std::string( cmd ), status, lines } );
}

}   // namespace rw::gitstampstore
