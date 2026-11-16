// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  diagnostics.cpp
//
//  The one out-of-line translation unit behind Diagnostics.h: the ConsoleLog report handlers (assert-family / panic /
//  thread-ownership violation / VALIDATE trace / degraded path) and the thread-id counter. Everything else in the
//  diagnostics system is macros, so every target and every standalone test harness in test/ links exactly this file
//  to satisfy ASSUME, EXPECTS, ENSURES, DASSERT, UNREACHABLE, VALIDATE, ASSUME_SAME_THREAD*, PANIC and
//  DISCLOSE.
//
#include "Diagnostics.h"
#include "emit.h"

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <format>
#include <mutex>
#include <string_view>
#include <utility>

namespace Diagnostics
{

// The build-flavour link check behind ThreadOwner (Diagnostics.h §2): only a debug diagnostics.cpp defines it, so a
// debug TU that constructs a ThreadOwner cannot link against a release one.
#if !defined( NDEBUG )
void debugFlavourLinkCheck() noexcept {}
#endif

namespace
{

// Two columns, one row per CheckKind in enum order: the banner, then who to suspect. The blame line is the reason
// EXPECTS and ENSURES exist as words — it is the first thing a reader of the report needs.
constexpr const char* kKindBanner[] = {
    "ASSUME FAILED",
    "EXPECTS FAILED (precondition)",
    "ENSURES FAILED (postcondition)",
    "DASSERT FAILED",
    "UNREACHABLE REACHED",
};
constexpr const char* kKindBlame[] = {
    "an invariant this function relies on is false here",
    "the CALLER broke this function's contract — look up the stack",
    "THIS function broke its own contract — look inside it",
    "a debug-only check is false (no release promise was made)",
    "control arrived where this function says it cannot",
};

// ── ONE NOTICE, ONE WRITE ────────────────────────────────────────────────────────────────────────────────────────
// Every reporter below formats its whole notice first and hands it to stderr in ONE stdio call. Built instead from a
// chain of `std::cerr <<` insertions, with stdio sync on (the default) each insertion is its own fwrite on an
// unbuffered stderr, so its own write(2): any other thread's single-write line can then land between two insertions
// and split the notice across lines. Measured on a gate whose fixture refuses two files at once: the degraded notice
// torn in 32-73% of runs depending on load, and 0 tears in 3,800 runs once it was written whole (test/diagnoticecheck.sh).
//
// WHY emitRaw OVER A RAW write( 2, … ). One stdio call holds the stream's lock for the whole call, so no other stdio
// writer in the process — which is every other stderr writer here — can interleave, at any length. Underneath, the
// unbuffered stderr hands the whole notice to the kernel as one write(2), measured up to the full buffer (4,094 bytes
// in one write) on macOS's libc and on glibc. A libc that split a long write would still do it with the lock held.
// A raw write(2) would add nothing for this process and would step OUTSIDE that lock, so a line another thread is
// writing through stdio could be split by the notice instead. Across PROCESSES sharing the descriptor, one write to a
// pipe is atomic only up to PIPE_BUF (512 bytes on macOS), and neither spelling changes that.
//
// NO ALLOCATION. A reporter may be running because memory ran out, so the notice is formatted into a fixed stack
// buffer through rw::formatTo, never into a std::string (which std::print and rw::emitTo both build). The buffer is
// a cap: a notice longer than it is cut, and the cut is DISCLOSED in the notice itself (markTruncated, below).
//
// STDOUT FIRST. std::cerr is tied to std::cout, so a chain of insertions flushes stdout before it writes. writeNotice
// keeps that: without it a trap or an abort right after the notice loses whatever stdout still held, and under
// `>file 2>&1` a notice lands ahead of output the program wrote before it. fflush allocates nothing.
inline constexpr std::size_t kNoticeByteCap = 4096;   // a longer notice is cut and says so: " ... [notice truncated: kept K of N bytes]"

// std::format on a null const char* is undefined, and a reporter must survive the malformed call it is reporting.
const char* orEmpty( const char* text ) noexcept
{
    return text != nullptr ? text : "";
}

// The optional "Notes:" row of the assert and thread-violation banners: three pieces, all empty without a description.
struct NotesRow
{
    const char* label;
    const char* text;
    const char* eol;
};

NotesRow notesRowOf( const char* description ) noexcept
{
    if( description != nullptr && description[ 0 ] != '\0' )
    {
        return NotesRow{ "  Notes:    ", description, "\n" };
    }
    return NotesRow{ "", "", "" };
}

// A notice past kNoticeByteCap keeps its opening and ends in a marker giving the bytes KEPT and the notice's full
// length (shown and total, never one ambiguous number), still on a line of its own. The cut backs off to a UTF-8 lead
// byte, so the kept text never ends inside a multi-byte sequence. K depends on the marker's length and the marker
// spells K, so the marker is first sized with the largest K it could carry; the real K is never longer.
void markTruncated( char* notice, std::size_t capacity, std::size_t fullBytes ) noexcept
{
    char       marker[ 96 ];   // 42 literal B + two 20-digit counts + NUL = 83
    const auto formatMarker = [ & ]( std::size_t kept ) noexcept
    {
        return rw::formatTo( marker, sizeof( marker ), " ... [notice truncated: kept {} of {} bytes]\n", kept, fullBytes );
    };
    std::size_t keptBytes = capacity - 1 - formatMarker( capacity - 1 );
    while( keptBytes > 0 && ( static_cast<unsigned char>( notice[ keptBytes ] ) & 0xC0 ) == 0x80 )
    {
        --keptBytes;
    }
    const std::size_t markerBytes = formatMarker( keptBytes );
    std::memcpy( notice + keptBytes, marker, markerBytes + 1 );
}

template<class... A>
RW_COLD void writeNotice( std::format_string<A...> format, A&&... args ) noexcept
{
    char              notice[ kNoticeByteCap ];
    const std::size_t fullBytes = rw::formatTo( notice, sizeof( notice ), format, std::forward<A>( args )... );
    if( fullBytes >= sizeof( notice ) )
    {
        markTruncated( notice, sizeof( notice ), fullBytes );
    }
    std::fflush( stdout );
    rw::emitRaw( stderr, notice );
    std::fflush( stderr );
}

// adoptNotices' sites, as "FILE:LINE" — the location a notice prints. Fixed storage, no allocation: read and written only
// on the cold notice path, and a site past the capacity (or longer than a slot) is not adopted, so it may print twice.
struct AdoptedSites
{
    static constexpr std::size_t kCapacity  = 64;    // sites a base child's notices adopt; past it a site may print twice (stderr only)
    static constexpr std::size_t kSlotBytes = 256;   // one site's FILE:LINE; a longer one is not adopted (stderr only)
    std::mutex                   mutex;
    char                         sites[ kCapacity ][ kSlotBytes ] = {};
    std::size_t                  count = 0;
};
AdoptedSites& adoptedSites() noexcept
{
    static AdoptedSites adopted;
    return adopted;
}

bool siteAdopted( const char* file, int line ) noexcept
{
    AdoptedSites&                     adopted = adoptedSites();
    const std::lock_guard<std::mutex> lock( adopted.mutex );
    if( adopted.count == 0 )
    {
        return false;
    }
    char              key[ AdoptedSites::kSlotBytes ];
    const std::size_t keyBytes = rw::formatTo( key, sizeof( key ), "{}:{}", orEmpty( file ), line );
    if( keyBytes >= sizeof( key ) )
    {
        return false;
    }
    for( std::size_t siteIndex = 0; siteIndex < adopted.count; ++siteIndex )
    {
        if( std::strcmp( adopted.sites[ siteIndex ], key ) == 0 )
        {
            return true;
        }
    }
    return false;
}

} // namespace

void ConsoleLog::adoptNotices( const char* stderrText ) noexcept
{
    // a notice line: "[math degraded] DESC  (FILE:LINE, FUNCTION — logged once per site)" or "[validate] … (same tail)".
    // FUNCTION is a pretty-printed signature, which holds no two-space run, so the location starts after the LAST "  (".
    constexpr std::string_view kTail = " — logged once per site)";
    std::string_view           text( stderrText == nullptr ? "" : stderrText );
    AdoptedSites&              adopted = adoptedSites();
    while( !text.empty() )
    {
        const std::size_t      eol  = text.find( '\n' );
        const std::string_view line = text.substr( 0, eol );
        text.remove_prefix( eol == std::string_view::npos ? text.size() : eol + 1 );
        if( !( line.starts_with( "[math degraded] " ) || line.starts_with( "[validate] " ) ) || !line.ends_with( kTail ) )
        {
            continue;
        }
        const std::size_t open = line.rfind( "  (" );
        const std::size_t comma = open == std::string_view::npos ? std::string_view::npos : line.find( ", ", open );
        if( comma == std::string_view::npos )
        {
            continue;
        }
        const std::string_view            site = line.substr( open + 3, comma - open - 3 );
        const std::lock_guard<std::mutex> lock( adopted.mutex );
        if( adopted.count < AdoptedSites::kCapacity && site.size() < AdoptedSites::kSlotBytes )
        {
            std::memcpy( adopted.sites[ adopted.count ], site.data(), site.size() );
            adopted.sites[ adopted.count ][ site.size() ] = '\0';
            ++adopted.count;
        }
    }
}

RW_COLD_NOINLINE
void ConsoleLog::handleAssert( CheckKind kind, const char* expr, const char* file, int line, const char* function,
                               const char* description ) noexcept
{
    const std::size_t row   = static_cast<std::size_t>( kind );
    const NotesRow     notes = notesRowOf( description );
    writeNotice( "\n======================================\n"
                 "!!! {} !!!\n"
                 "======================================\n"
                 "  Expr:     {}\n"
                 "  Blame:    {}\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "{}{}{}"
                 "======================================\n",
                 kKindBanner[ row ], orEmpty( expr ), kKindBlame[ row ], orEmpty( file ), line, orEmpty( function ),
                 notes.label, notes.text, notes.eol );
    RW_TRAP();
}

[[noreturn]] RW_COLD_NOINLINE
void ConsoleLog::handlePanic( const char* file, int line, const char* function, const char* description ) noexcept
{
    writeNotice( "\n======================================\n"
                 "!!! CRITICAL SYSTEM PANIC !!!\n"
                 "======================================\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "  Reason:   {}\n"
                 "======================================\n",
                 orEmpty( file ), line, orEmpty( function ), orEmpty( description ) );
    std::abort();
}

RW_COLD_NOINLINE
void ConsoleLog::handleThreadViolation( std::uint64_t expected, std::uint64_t got, const char* file, int line, const char* function,
                                        const char* description ) noexcept
{
    const NotesRow notes = notesRowOf( description );
    writeNotice( "\n======================================\n"
                 "!!! THREAD-OWNERSHIP VIOLATION !!!\n"
                 "======================================\n"
                 "  This site or object is single-thread owned but was reached from another thread.\n"
                 "  Owner thread: {}   Offending thread: {}\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "{}{}{}"
                 "======================================\n",
                 expected, got, orEmpty( file ), line, orEmpty( function ), notes.label, notes.text, notes.eol );
    RW_TRAP();
}

RW_COLD_NOINLINE
void ConsoleLog::handleValidateFailed( const char* expr, const char* file, int line, const char* function, const char* description ) noexcept
{
    // One line, no trap: a false VALIDATE is input being refused, which is the program working.
    const bool  hasDescription = description != nullptr && description[ 0 ] != '\0';
    const char* separator      = hasDescription ? " — " : "";
    const char* text           = hasDescription ? description : "";
    if( siteAdopted( file, line ) )
    {
        return;   // the child that ran an earlier phase of this run already printed it (adoptNotices)
    }
    writeNotice( "[validate] {} is false{}{}  ({}:{}, {} — logged once per site)\n",
                 orEmpty( expr ), separator, text, orEmpty( file ), line, orEmpty( function ) );
}

RW_COLD_NOINLINE
void ConsoleLog::handleDegraded( const char* file, int line, const char* function, const char* description ) noexcept
{
    // DISCLOSE's debug trace. One-line notice, no trap — the caller clamps/falls back and continues. The
    // "[math degraded]" prefix and every message are kept byte-identical: 11 gates grep for the prefix
    // (test/*.sh on 3bf884e2) and test/sidecarsymlinkcheck.sh pins message text. Retiring the prefix is its own change.
    if( siteAdopted( file, line ) )
    {
        return;   // the child that ran an earlier phase of this run already printed it (adoptNotices)
    }
    writeNotice( "[math degraded] {}  ({}:{}, {} — logged once per site)\n", orEmpty( description ), orEmpty( file ), line, orEmpty( function ) );
}

// Unique, stable, non-zero per-thread id. thread_local counter avoids pulling <thread> into the widely-included
// Diagnostics.h; first thread to ask gets 1, next 2, etc. Non-zero so 0 stays a valid "unclaimed" sentinel for the
// per-site latch and ThreadOwner.
std::uint64_t currentThreadId() noexcept
{
    static std::atomic<std::uint64_t> counter{ 0 };
    thread_local const std::uint64_t  id = ++counter;
    return id;
}

} // namespace Diagnostics
