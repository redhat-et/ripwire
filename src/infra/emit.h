#pragma once

// emit.h — THE formatted-output emitter, and the ONE place the std::print-versus-std::format choice is made.
//
// WHY A CHOICE AT ALL. The house rule (CONTRIBUTING.md §3 "Output") is std::print; the tree is printf-family
// by history and converting it is byte-parity-fenced by test/printffmtparitycheck.sh. <print> arrives in
// libstdc++ 14 and, on libc++, only at a macOS 14+ deployment target — and libc++ defines __cpp_lib_print
// only when the target admits it (measured 2026-09-08 with Apple clang 21: defined at -mmacosx-version-min
// 14.0, absent at 13.0), so testing the FEATURE MACRO rather than the header's presence is what keeps a
// lower target compiling instead of failing on an unavailable symbol. Every toolchain therefore builds:
// std::print where the library has it, std::format rendered and written with std::fputs where it does not.
//
// WHY THE CHOICE IS DISCLOSED. A silent fallback would let a CI leg on gcc 13 read as "the std::print floor
// holds". kEmitterName names the path that compiled in; --version prints it as emit= (gated by
// test/versioncheck.sh #6) and each CI leg asserts the value it is supposed to have (.github/workflows).
//
// CONTRACT PARITY. std::fputs reports a failed write by return value, which every emitting site here has
// always ignored; std::print reports it by THROWING std::system_error. The std::print arm catches that one
// exception so the two arms keep one contract — a write failure is silent on both, exactly as before the
// conversion, and never a std::terminate the fputs arm could not produce. (A closed pipe is SIGPIPE on
// both arms and reaches neither.) fmt is NOT vendored: the standard library has the feature, so a vendored
// copy would be a G3 regression.

#include "Diagnostics.h"   // DISCLOSE — renderToString's open_memstream degrade, below
#include "os.h"            // rw::os::open_memstream — the MemoryStream buffer

#include <cstddef>
#include <cstdint>        // std::uint8_t — Rendered::DisclosureWhy
#include <cstdlib>
#include <new>            // std::bad_alloc — renderToString's injected emitter-throw fault, below
#include <type_traits>
#include <cstring>
#include <cstdio>
#include <format>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <version>
#if __has_include( <print> )
#include <print>
#endif

namespace rw
{

// EMIT_FORCE_FALLBACK selects the std::format+fputs arm on a toolchain that would otherwise
// take the <print> one, so both arms can be diffed locally instead of only in one CI job.
#if defined( __cpp_lib_print ) && __cpp_lib_print >= 202207L && !defined( EMIT_FORCE_FALLBACK )

inline constexpr const char* kEmitterName = "std::print";

template<class... A> inline void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    try
    {
        std::print( stream, f, std::forward<A>( a )... );
    }
    catch( const std::system_error& )
    {
        // fputs's contract, kept: a failed write is silent (see the header comment).
    }
}

#else

inline constexpr const char* kEmitterName = "std::format+fputs";

template<class... A> inline void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    std::fputs( std::format( f, std::forward<A>( a )... ).c_str(), stream );
}

#endif


// ── emitRaw — literal text, which is not a format string at all ──────────────────────────────────────
// 353 of this tree's printf-family calls pass a string and NO arguments: help pages, legends, usage
// banners, XML preambles. Routing those through emitTo would be worse than pointless — std::format_string
// is CONSTEVAL, so each would pay compile-time parsing for formatting that never happens, and the --help
// table at 114,985 characters exceeds the constant-evaluation budget outright and does not compile.
//
// THE TRAP WHEN CONVERTING INTO THIS: a printf format spells a literal percent %%, and text passed to
// fputs is no longer a format, so %% here would print TWO characters and must become a single %. Braces
// are the mirror image: emitTo needs {{ and }} where this needs a bare { and }.
template<class S> inline void emitRaw( std::FILE* stream, const S& text )
{
    std::fputs( text, stream );
}

// ── cstr — a fixed char[] holds a C STRING, and `{}` must be told so ─────────────────────────────────
// printf's %s on a `char buf[N]` always meant ONE thing: the bytes up to the first NUL. The array itself
// is a different object, and what `{}` means for a char[N] argument has not been uniform across library
// versions — an implementation that formats the ARRAY emits the trailing NUL and whatever uninitialised
// bytes follow it, which in this tool lands inside an XML attribute and produces a document that does not
// parse. The buffers here are routinely written short and reused, so that difference is not theoretical.
//
// Decaying explicitly removes the question on every implementation, and says at the call site which of the
// two readings was meant. Pass a fixed buffer as rw::cstr( buf ), never bare.
inline const char* cstr( const char* p ) noexcept { return p; }

// ── formatTo — snprintf's SHAPE, kept ────────────────────────────────────────────────────────────────
// std::snprintf's other half of this tree renders into a CALLER-OWNED char buffer rather than a stream,
// so emitTo is the wrong tool for it: routing those sites through std::format and a std::string would
// put an allocation on serialize.h's per-symbol path, which is a G2 regression, not a modernisation.
// std::format_to_n keeps the stack buffer and adds nothing.
//
// The contract is snprintf's, exactly, so the call sites need no reasoning about the difference:
//   - writes at most cap-1 characters and ALWAYS NUL-terminates when cap > 0;
//   - returns the length the output WOULD have had, untruncated — snprintf's return, which is what the
//     truncation-detecting call sites read;
//   - cap == 0 writes nothing and still reports that length.
//
// Only ONE arm, unlike emitTo: std::format_to_n is <format> (C++20), present on every toolchain that
// builds this tree, so there is nothing to feature-test and nothing to disclose.
//
// WHY THIS IS A SAFETY FIX AND NOT ONLY A STYLE ONE: snprintf returns the would-have-written length, so
// the append idiom `p += snprintf( p, e - p, ... )` walks p PAST e on truncation and the next
// size_t( e - p ) underflows into an unbounded write. Three lambdas in serialize.h carry a hand-written
// clamp against exactly that (see their A4-F8 comments). format_to_n returns the ACTUAL end of the
// written region, already bounded by the n it was given, so the clamp becomes structural and the bug
// class stops existing rather than being defended against site by site.
template<class... A> inline std::size_t formatTo( char* buf, std::size_t cap, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
                               && !std::is_const_v<std::remove_extent_t<std::remove_reference_t<A>>> ) ),
                   "pass rw::cstr( buf ) for a fixed char buffer: {} on a char[N] is not printf's %s" );
    if( cap == 0 )
    {
        return std::formatted_size( f, std::forward<A>( a )... );
    }
    const auto r = std::format_to_n( buf, static_cast<std::ptrdiff_t>( cap - 1 ), f, std::forward<A>( a )... );
    *r.out = '\0';
    return static_cast<std::size_t>( r.size );
}

// ── THE render-an-emitter-into-a-string seam ─────────────────────────────────────────────────────────
// An emitter writes to a FILE*. A caller that must MEASURE what it wrote (a budget ladder pricing its own
// document before it commits to a trim level) or REORDER it (a legend whose wording depends on the body that
// follows it in the stream) needs those bytes as a string first. That is one seven-line memstream dance, and
// it was hand-written at each such site.
//
// Review of #214: the copy in prcontext.h returned "" on failure with NO alert, and the unbudgeted
// --pr-context path had just been routed through it — so an open_memstream failure would have shipped a
// legend, a root tag and a closing tag around an EMPTY body, with truncated="none" saying nothing was cut.
// A degrade has to be visible and the caller has to be able to see it: `ok` is false exactly when the bytes
// returned are not the bytes the emitter wrote (and then `text` is empty), the alert names the site through
// the caller's own message — "which buffer failed" is the useful half — and the caller then takes its own
// documented path. Never a silent empty body, and never a silent SHORT one.
//
// CodeRabbit on #214: the first version asked open_memstream and then ignored what fflush and fclose
// answered, setting ok=true regardless. Reading `buf`/`sz` after a failed write is exactly how a TRUNCATED
// document passes for a whole one — the same defect as the empty body above, one size smaller and harder to
// see. The fix checked fflush and fclose, on the reasoning that an allocation failure the per-row fwrites
// swallowed surfaces at the FLUSH. MEASURED later, it does not, on macOS: see MemoryStream below, which reads the
// stream's error flag as well and is now the one owner of every memstream in the tree.
struct Rendered
{
    std::string text;
    bool        ok = false;
    // The DISCLOSE sink for renderToString's three failures: each leaves `ok` false and `text` empty — the value every
    // caller is handed, and must read, instead of a partial buffer.
    enum class DisclosureWhy : std::uint8_t
    {
        BufferFailed,   // the memory stream did not open, or did not finish whole
        EmitterThrew,   // the emitter threw part-way
        CopyThrew,      // the copy out of a complete buffer threw
    };
    void disclose( DisclosureWhy ) noexcept
    {
        ok = false;
        text.clear();
    }
};

// ── THE EMITTER ITSELF MAY THROW, and that is a degrade, not a way out ───────────────────────────────
// The emitter was called outside any handler. A throw from it — std::bad_alloc out of the std::format
// fallback is the reachable one, since the whole point of this seam is to buffer a document whose size is
// not known in advance — skipped the fclose, the free, the alert and the documented empty-result fallback in
// one jump: the memstream and its buffer leaked, and the caller got an exception where its contract says it
// gets `ok == false`.
//
// The answer is the one this layer gives everywhere a throw crosses a seam that owns a resource: catch AT
// the seam, release what it owns, DISCLOSE, and hand back the degraded value the caller already reads. It is
// the same answer this function gives when open_memstream fails, so callers need no new case — `ok == false`
// has always meant "these are not the bytes the emitter wrote", and a caller that has a fallback for the
// empty buffer has one for this.
//
// FAULT INJECTION, because a throw path is otherwise unreachable from a test: non-NDEBUG only (so it is
// `constexpr false` and the getenv is deleted in release: zero release cost), read ONCE per process (so it
// cannot change mid-document and determinism holds), and EXACT "1" is the only ON value, because the
// contract is a switch — a prefix test would let "=10" and "=0" mean whatever the reader guessed, which is a
// defect worth fixing once, here, rather than once per switch.
//
// THE ENV NAME CARRIES THIS LAYER'S PREFIX, NOT THE HOST'S. Everything under infra/ is built to travel to
// another repository; a host-named switch would arrive there describing a program its reader has never run,
// which is exactly what the layering gate refuses. A host that owns its own fault switches names them its
// own way and reads them through faultSwitchOn below.
#ifndef NDEBUG
inline bool faultSwitchOn( const char* envName ) noexcept
{
    const char* value = std::getenv( envName );
    return value != nullptr && std::strcmp( value, "1" ) == 0;
}
#else
inline constexpr bool faultSwitchOn( const char* ) noexcept { return false; }
#endif

// Each switch keeps its own named wrapper and its own once-per-process read: the name is what a reader greps
// for, and the `static` is what keeps the answer from changing mid-document (determinism).
inline bool isRenderEmitThrowFaultInjected() noexcept
{
    static const bool isOn = faultSwitchOn( "INFRA_FAULT_RENDER_EMIT_THROW" );
    return isOn;
}

// The SECOND throwing site, and its own switch for the same reason the first has one: the name is what a
// reader greps for. The emitter is not the only allocation here — the final copy out of the memstream buffer
// is one too, and it sat outside the handler that the emitter's throw takes.
inline bool isRenderCopyThrowFaultInjected() noexcept
{
    static const bool isOn = faultSwitchOn( "INFRA_FAULT_RENDER_COPY_THROW" );
    return isOn;
}

// ── THE MEMORY STREAM: an owned open_memstream whose bytes come back whole, or not at all ─────────────────
// Every `open_memstream` in this tree ended the same way, written by hand at each site: flush, close, then read
// `buf`/`sz`. The result of that close was thrown away at twenty-two of them, and at the one that did check (this
// file's renderToString, after CodeRabbit on #214) the check could not see the failure it was written for.
//
// MEASURED 2026-09-16, not assumed: a DYLD interposer that fails ONE chosen realloc call, run against open_memstream on
// macOS 26.5.1 (Apple libc), over 5 KB, 50 KB and 200 KB streams written in 1 KB chunks. All 19 runs whose injection
// landed inside the stream made exactly one fwrite short and set the stream's error flag. Each lost 152 to 976 bytes,
// as late as chunk 177 of 200, so the hole is in the middle of the document and `sz` comes back short. fflush and
// fclose BOTH RETURNED 0 in all 19. So checking fflush and fclose alone passes a document with a hole in it. The error
// indicator is what records a lost write (POSIX ferror), so finish() reads it after the flush, before the close.
//
// THE SHAPE: a holder, because the stream and its buffer are two resources with one lifetime, and a value, because a
// failure is an answer the caller must branch on, never an exception (this layer does not throw).
//   open()      opens through open_memstream, or through a caller's own opener with the same signature (serialize.h's
//               fault-injectable openChargeBuffer). nullptr when the open fails; the caller takes its degrade.
//   finish()    flush, read the error flag, close, exactly once, and report BY VALUE: `isWhole` is true only when the
//               flush succeeded, no write ever failed, the close succeeded (the close is what publishes the buffer and
//               its size) and the buffer exists. `bytes` views the buffer, and is empty unless the stream is whole.
//               [[nodiscard]]: a caller that does not read the answer is the defect this type exists to end.
//   ~MemoryStream  closes a stream nobody finished (an early return, a throw from the writer) and frees the buffer on
//               every path, so no site frees or closes anything by hand. NOT movable: libc holds the addresses of the
//               buffer pointer and the size, so the object must stay where it was opened.
// test/estchargecheck.sh #14g refuses an open_memstream, or a fflush/fclose of one, anywhere outside this class and
// the one opener it is handed; #14f drives every caller's degrade through the fault switch below.
//
// FAULT INJECTION, the same shape as the two switches above: INFRA_FAULT_MEMSTREAM_FINISH=1 on a non-NDEBUG build makes
// every finish() report failure AFTER really closing the stream. Read once per process; constexpr false in release.
inline bool isMemstreamFinishFaultInjected() noexcept
{
    static const bool isOn = faultSwitchOn( "INFRA_FAULT_MEMSTREAM_FINISH" );
    return isOn;
}

struct MemoryStreamBytes
{
    std::string_view bytes;             // the whole document, valid while its MemoryStream lives; empty unless isWhole
    bool             isWhole = false;
};

class MemoryStream
{
public:
    MemoryStream() noexcept = default;
    MemoryStream( const MemoryStream& )            = delete;
    MemoryStream& operator=( const MemoryStream& ) = delete;
    MemoryStream( MemoryStream&& )                 = delete;   // libc holds &m_buf and &m_size
    MemoryStream& operator=( MemoryStream&& )      = delete;

    ~MemoryStream()
    {
        if( m_file != nullptr )
        {
            std::fclose( m_file );   // unfinished: its bytes were never read, so its answer has nobody to tell
        }
        std::free( m_buf );
    }

    [[nodiscard]] std::FILE* open() noexcept { return openWith( []( char** buf, std::size_t* size ) noexcept { return os::open_memstream( buf, size ); } ); }

    template<class Opener>
    [[nodiscard]] std::FILE* openWith( Opener&& opener ) noexcept
    {
        if( m_file == nullptr && !m_isFinished )
        {
            m_file = opener( &m_buf, &m_size );
        }
        return m_file;
    }

    [[nodiscard]] bool isOpen() const noexcept { return m_file != nullptr; }

    [[nodiscard]] MemoryStreamBytes finish() noexcept
    {
        if( m_file == nullptr )
        {
            return {};
        }
        const bool isFlushed   = std::fflush( m_file ) == 0;
        const bool isErrorFree = std::ferror( m_file ) == 0;
        const bool isClosed    = std::fclose( m_file ) == 0;
        m_file       = nullptr;
        m_isFinished = true;
        const bool isWhole = isFlushed && isErrorFree && isClosed && m_buf != nullptr && !isMemstreamFinishFaultInjected();
        return isWhole ? MemoryStreamBytes{ std::string_view( m_buf, m_size ), true } : MemoryStreamBytes{};
    }

private:
    std::FILE*  m_file       = nullptr;
    char*       m_buf        = nullptr;
    std::size_t m_size       = 0;
    bool        m_isFinished = false;
};

template<class Emit>
inline Rendered renderToString( Emit&& emit )
{
    Rendered     out;
    MemoryStream stream;
    std::FILE* const m = stream.open();
    if( m == nullptr )
    {
        DISCLOSE( out, Rendered::DisclosureWhy::BufferFailed, "renderToString: the memory buffer did not open — the caller takes its documented fallback" );
        return out;
    }
    try
    {
        // The injected fault stands exactly where a real std::bad_alloc would escape: the stream is open and
        // nothing has been cleaned up yet, which is the state the catch below exists to unwind.
        if( isRenderEmitThrowFaultInjected() ) { throw std::bad_alloc(); }
        emit( m );
    }
    catch( ... )
    {
        // What this function owns is released by `stream` on the way out: the unfinished stream is closed and its
        // buffer freed, once. `out` is still the default-constructed failure — empty text, ok == false.
        // Its own reason, not the buffer's: the emitter threw. The caller is named anyway, because __PRETTY_FUNCTION__
        // carries the Emit lambda's own file and line.
        DISCLOSE( out, Rendered::DisclosureWhy::EmitterThrew, "renderToString: the emitter THREW — nothing was measured, "
                                                              "the caller takes its documented fallback" );
        return out;
    }
    // MemoryStream::finish owns the order (flush, error flag, close) and the null-buffer rule — an emitter that wrote
    // nothing still gets a zero-length, null-terminated buffer, so null is itself a failure.
    const MemoryStreamBytes rendered = stream.finish();
    out.ok = rendered.isWhole;
    if( out.ok )
    {
        // THE LAST ALLOCATION IS STILL AN ALLOCATION. This copy is the one throwing statement on the success
        // path, and it used to stand outside every handler: a std::bad_alloc here escaped a function whose
        // contract is that a failure is ALERTED and returned as ok == false. It is caught here, and the buffer is
        // freed by `stream` either way.
        try
        {
            // The injected fault stands exactly where a real std::bad_alloc would: the buffer is complete
            // and closed, and the copy of it is what fails.
            if( isRenderCopyThrowFaultInjected() ) { throw std::bad_alloc(); }
            out.text.assign( rendered.bytes );
        }
        catch( ... )
        {
            // Neither the buffer nor the emitter: the copy out of a complete buffer threw. Its own reason, so the trace
            // says which of the three failures it hit; the sink empties `text` and clears `ok`.
            DISCLOSE( out, Rendered::DisclosureWhy::CopyThrew, "renderToString: the final COPY out of the buffer THREW — nothing was "
                                                           "measured, the caller takes its documented fallback" );
        }
    }
    else
    {
        DISCLOSE( out, Rendered::DisclosureWhy::BufferFailed, "renderToString: the memory buffer did not finish whole — the caller takes its documented fallback" );
    }
    return out;
}

}   // namespace rw
