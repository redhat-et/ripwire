// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  agenttrap.h
//
//  AGENT-VISIBLE-TRAP: what a failed dev-build ASSUME / EXPECTS / ENSURES / UNREACHABLE tells an AGENT, not only a
//  person at a debugger. Agents do not attach a debugger. Before this, the failure path wrote its notice to stderr
//  and trapped, so:
//    - over MCP the model saw a dead server (stderr goes to the client's log, and the in-flight request never got a
//      response);
//    - on the CLI the agent saw an empty answer.
//  A graded sit counted 4 such aborts as 10 lost items until a person opened the empty outputs.
//
//  Before the trap, the failure path (diagnostics.cpp, ConsoleLog::handleAssert) now also writes:
//    1. MCP, a request in flight: a JSON-RPC error for that request's id, framed the way the transport frames
//       (stdio: one JSON line on stdout; --listen: an HTTP/1.1 response with Content-Length on the request's socket).
//       code -32603, data {kind, expr, file, line, function, note, version, built_from, hint}.
//    2. CLI: one `<ripwire_internal_error …/>` line on stdout, XML-escaped like the CLI's own answers.
//    3. Both: a `last-crash` record in the cache directory. The next CLI call (stderr) and the next MCP
//       `initialize` (stderr + the instructions text) print one line naming it, then remove it.
//  The stderr notice is kept, and the trap is kept (see diagnostics.cpp "WHY THE TRAP STAYS").
//
//  STATE. One process-global slot, not a thread_local: both MCP transports are single-threaded loops, and a check
//  that fails on a verb's WORKER thread is still that request's failure, so the slot the dispatcher set must be
//  visible from every thread. The slot is armed once by main (transport, argv, version, cache dir) and set and
//  cleared per request by the transport loop (beginRequest after the id is read, endRequest after the response is
//  flushed). Everything the failure path writes is preformatted into fixed static buffers; nothing is allocated
//  after the check fails.
//
//  RELEASE BUILDS. Every function below is an empty inline under NDEBUG, and the call sites that would compute an
//  argument (the cache dir, the take) are inside `#if !defined( NDEBUG )`. A release binary has no new code: its
//  ASSUME family is [[assume]] and never reaches a handler. DASSERT and VALIDATE are unchanged in every build.
//
//  THE TEST TRIGGER. RIPWIRE_TEST_TRAP=assume|expects|ensures|unreachable fires that check from fireTestTrap(),
//  which main calls on the CLI path and dispatchMcpLine calls inside tools/call (test/agenttrapcheck.sh). Debug
//  builds only: under NDEBUG the function is empty and the variable is never read.
//

#pragma once

#include <cstddef>

namespace Diagnostics::agenttrap
{

// How the failure path reaches the agent. None = stderr only (every standalone test harness, and --lsp, whose
// stdout is Content-Length framed for an editor that would read a stray line as a broken frame).
enum class Transport : unsigned char
{
    None,
    Cli,        // one <ripwire_internal_error/> line on stdout
    McpStdio,   // one JSON-RPC line on stdout, for the request in flight
    McpHttp,    // one HTTP/1.1 response on the request's socket, for the request in flight
};

// The OS calls the failure path and the record reader make, handed over by main (agenttrap_os.h fills it from rw::os).
// diagnostics.cpp is linked ALONE into every standalone test harness, so it reaches no OS layer itself: a null table is
// the unarmed state, and then nothing but the stderr notice is written. Every entry must be callable after a failed
// check: no allocation, no lock a failing thread could hold.
struct OsCalls
{
    long long ( *write )( int fd, const char* bytes, std::size_t count ) noexcept           = nullptr;   // stdout, the record
    long long ( *send )( int socket, const char* bytes, std::size_t count ) noexcept        = nullptr;   // the --listen socket
    int ( *createTruncate )( const char* path ) noexcept                                    = nullptr;   // 0600, for writing
    void ( *close )( int fd ) noexcept                                                      = nullptr;
    int ( *rename )( const char* from, const char* to ) noexcept                            = nullptr;
    int ( *remove )( const char* path ) noexcept                                            = nullptr;
    std::size_t ( *readPrefix )( const char* path, char* into, std::size_t capacity ) noexcept = nullptr;
    long long ( *processId )() noexcept                                                     = nullptr;
};

// What the failure path names, set once by main before any verb runs. Strings are copied (capped) into static
// buffers, so the caller's storage may die. `cacheDir` is where `last-crash` lives (quality.h cacheDirLadder).
struct ArmInfo
{
    Transport          transport = Transport::None;
    int                argc      = 0;
    const char* const* argv      = nullptr;
    const char*        version   = "";
    const char*        builtFrom = "";
    const char*        cacheDir  = "";
    OsCalls            os;
};

// The record the previous call left, if any: its one-line summary and the path it was read from.
inline constexpr std::size_t kSummaryCap = 2048;
struct TakenCrash
{
    bool        found = false;
    char        summary[ kSummaryCap ];
    std::size_t summaryBytes = 0;
};

#if !defined( NDEBUG )

void arm( const ArmInfo& info ) noexcept;

// The dispatcher's slot. `idToken` is the request's raw JSON id token (a number, a quoted string or null), echoed
// verbatim; an id longer than the slot is answered with null, which JSON-RPC 2.0 allows when the id cannot be
// echoed. `httpFd` is the connection's socket for Transport::McpHttp, -1 otherwise. A notification (no id) never
// begins a request: no response is due, so the failure path writes none.
void beginRequest( const char* idToken, std::size_t idBytes, int httpFd ) noexcept;
void noteTool( const char* name, std::size_t nameBytes ) noexcept;   // tools/call's tool name, for the record
void endRequest() noexcept;                                          // after the response is flushed

// Reads `<cacheDir>/last-crash` once, removes it, and returns its summary line. Renamed aside before it is read, so
// of two calls racing for one record exactly one reports it. Ordinary code, not the failure path.
TakenCrash  takeLastCrash() noexcept;
const char* lastCrashPath() noexcept;   // "" when unarmed

void fireTestTrap() noexcept;

#else

inline void       arm( const ArmInfo& ) noexcept {}
inline void       beginRequest( const char*, std::size_t, int ) noexcept {}
inline void       noteTool( const char*, std::size_t ) noexcept {}
inline void       endRequest() noexcept {}
inline TakenCrash takeLastCrash() noexcept { return TakenCrash{}; }
inline const char* lastCrashPath() noexcept { return ""; }
inline void       fireTestTrap() noexcept {}

#endif

} // namespace Diagnostics::agenttrap
