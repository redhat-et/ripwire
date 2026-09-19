// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  Diagnostics.h
//
//  The self-check vocabulary. Implementations of the report handlers live in diagnostics.cpp; this header is
//  declarations and macros only, and stays library-free (<cstdint>, plus <atomic> in debug) so every standalone
//  harness in test/ can include it — test/noaliascheck.sh arm 5 compiles it with no other library header.
//
//  word                     promises                                 debug                         release (-DNDEBUG)
//  ASSUME( e[, "msg"] )     an invariant THIS code guarantees         check, report, trap           assumed, NOT evaluated
//  EXPECTS( e[, "msg"] )    ASSUME at function entry                  … report blames the CALLER    assumed, NOT evaluated
//  ENSURES( e[, "msg"] )    ASSUME before a return                    … report blames THIS function assumed, NOT evaluated
//  ASSUME_NO_ALIAS( a, b )  a and b are separate allocations (+3, _BUF) object check               separate_storage fact
//  ASSUME_SAME_THREAD()     this SITE only ever runs on one thread    per-site owner latch          nothing
//  ASSUME_SAME_THREAD_AS(o) object o is only touched by one thread    per-object owner id           nothing, no storage
//  DASSERT( e[, "msg"] )    nothing — worth checking, not promising    check, report, trap           nothing, NOT evaluated
//  UNREACHABLE( ["msg"] )   control never gets here                   report, trap                  __builtin_unreachable()
//  VALIDATE( e[, "msg"] )   nothing — e is EXTERNAL input             evaluated; trace once if false evaluated; one compare
//  PANIC( "msg" )           a corrupt state we cannot continue from   report, abort                 report, abort
//  DISCLOSE( sink, why[, "msg"] )  the answer says it is incomplete  sink.disclose( why ), trace  sink.disclose( why ) — ships
//  DISCLOSE( msg )          NOTHING — a debug trace only (§4b, ratchet) trace once per site           NOTHING: the user is not told
//  (sinks answerUnchanged / answerRefused: the degrade changes only cost / the verb refuses the answer by name — §4b)
//
//  The line between ASSUME and VALIDATE is the whole design: ASSUME hands the optimizer a fact and costs nothing in
//  release, so it is ONLY for predicates this code makes true; VALIDATE is for anything that crossed the process
//  boundary (argv, a file, git's output, a socket) and is evaluated in every build. Use ASSUME liberally on real
//  invariants — that is the point of the vocabulary — and never on input.
//

#pragma once

#include <cstdint>
#if !defined( NDEBUG )
  #include <atomic>   // the per-site latches (ASSUME_SAME_THREAD, VALIDATE's trace) and ThreadOwner's id — debug only
#endif

// --------------------------------------------------------------------------------------------------------------------
// 0. Name collisions — refused loudly, never silently redefined
//
// Every word below is short and conventional, which is exactly why a third-party header may already own it: MFC/ATL
// define ASSERT, VERIFY and ENSURE; doctest defines CHECK and REQUIRE (vendored, used by test/verify_*.cpp); the
// Windows port (#44) brings the SDK headers in. A second #define of a function-like macro with a different body is
// only a warning, and whichever definition comes LAST wins — so a collision would quietly swap an optimizer
// assumption for somebody else's always-on check, or the reverse. Include this header after any platform header;
// src/infra/os.h repeats these guards after <windows.h> for the same reason.
// --------------------------------------------------------------------------------------------------------------------
#if defined( ASSUME ) || defined( EXPECTS ) || defined( ENSURES ) || defined( DASSERT ) || defined( UNREACHABLE )
  #error "Diagnostics.h: ASSUME / EXPECTS / ENSURES / DASSERT / UNREACHABLE is already defined by an earlier header"
#endif
#if defined( VALIDATE ) || defined( PANIC ) || defined( ASSUME_NO_ALIAS ) || defined( ASSUME_NO_ALIAS3 ) || defined( ASSUME_NO_ALIAS_BUF )
  #error "Diagnostics.h: VALIDATE / PANIC / ASSUME_NO_ALIAS* is already defined by an earlier header"
#endif
#if defined( ASSUME_SAME_THREAD ) || defined( ASSUME_SAME_THREAD_AS ) || defined( DISCLOSE )
  #error "Diagnostics.h: ASSUME_SAME_THREAD / ASSUME_SAME_THREAD_AS / DISCLOSE is already defined by an earlier header"
#endif

// --------------------------------------------------------------------------------------------------------------------
// 1. __FILE_NAME__ — short filename without directory path
// --------------------------------------------------------------------------------------------------------------------
#if defined( __clang__ ) || ( defined( __GNUC__ ) && __GNUC__ >= 12 )
  #define _SHORTERFILE_ __FILE_NAME__
#else
  #define _SHORTERFILE_ __FILE__
#endif

// handleAssert and handleThreadViolation end in __builtin_trap, but in diagnostics.cpp, out of the static analyzer's
// sight. Without this it walks on past a failed ASSUME and reports exactly what the ASSUME ruled out — an
// out-of-bounds read of an index the ASSUME had just bounded. analyzer_noreturn informs the analyzer ONLY; codegen is
// untouched, unlike [[noreturn]], which would let the optimizer drop whatever follows the call. GCC has no such
// attribute and warns on it, hence the guard.
#if defined( __clang__ )
  #define DIAGNOSTICS_ANALYZER_NORETURN __attribute__( ( analyzer_noreturn ) )
#else
  #define DIAGNOSTICS_ANALYZER_NORETURN
#endif

// --------------------------------------------------------------------------------------------------------------------
// 2. Handler declarations — implemented in diagnostics.cpp
// --------------------------------------------------------------------------------------------------------------------
namespace Diagnostics
{
// Which word failed. The report names the blame, because that is what tells the reader where to look: a failed
// EXPECTS is the CALLER's bug, a failed ENSURES is this function's, a failed ASSUME is this function's invariant.
enum class CheckKind : std::uint8_t
{
    Assume,
    Expects,
    Ensures,
    DAssert,
    Unreachable,
};

namespace detail
{
// A view can share one allocation with another view; ASSUME_NO_ALIAS_BUF refuses them at compile time (§6). Detected
// structurally so this header stays library-free (no <span>/<string_view>/<type_traits>): std::span is the standard
// type with a static `extent`; std::basic_string_view has `traits_type` and, unlike basic_string, no `allocator_type`.
// A custom view is the author's own contract to keep.
template<class T> struct StripCvRef { using type = T; };
template<class T> struct StripCvRef<const T> { using type = T; };
template<class T> struct StripCvRef<volatile T> { using type = T; };
template<class T> struct StripCvRef<const volatile T> { using type = T; };
template<class T> struct StripCvRef<T&> { using type = typename StripCvRef<T>::type; };
template<class T> struct StripCvRef<T&&> { using type = typename StripCvRef<T>::type; };
template<class T> using Bare = typename StripCvRef<T>::type;
template<class T> concept HasStaticExtent = requires { Bare<T>::extent; };
template<class T> concept HasTraitsNoAllocator = requires { typename Bare<T>::traits_type; } && !requires { typename Bare<T>::allocator_type; };
template<class T> inline constexpr bool isView = HasStaticExtent<T> || HasTraitsNoAllocator<T>;
} // namespace detail

class ConsoleLog
{
public:
    [[gnu::cold, gnu::noinline]]
    static void handleAssert( CheckKind kind, const char* expr, const char* file, int line, const char* function,
                              const char* description ) noexcept DIAGNOSTICS_ANALYZER_NORETURN;

    [[gnu::cold, gnu::noinline, noreturn]]
    static void handlePanic( const char* file, int line, const char* function, const char* description ) noexcept;

    // ASSUME_SAME_THREAD / ASSUME_SAME_THREAD_AS: a site or object already claimed by one thread was reached from another.
    [[gnu::cold, gnu::noinline]]
    static void handleThreadViolation( std::uint64_t expected, std::uint64_t got, const char* file, int line, const char* function,
                                       const char* description ) noexcept DIAGNOSTICS_ANALYZER_NORETURN;

    // VALIDATE came back false. A one-line trace, once per site, never a trap: rejecting bad input is the program
    // working, and the caller's refusal or degrade path is what the user sees.
    [[gnu::cold, gnu::noinline]]
    static void handleValidateFailed( const char* expr, const char* file, int line, const char* function, const char* description ) noexcept;

    // DISCLOSE's debug trace — one-line notice, never traps, debug only (§4b). The "[math degraded]" prefix is what 11
    // gates grep for; it stays byte-identical, as do the messages.
    [[gnu::cold, gnu::noinline]]
    static void handleDegraded( const char* file, int line, const char* function, const char* description ) noexcept;
};

// Opaque, stable, NON-ZERO id for the calling thread (lives for the thread's lifetime). Implemented with a
// thread_local counter so no <thread> include is forced on every TU that pulls in Diagnostics.h.
std::uint64_t currentThreadId() noexcept;

// The per-object owner behind ASSUME_SAME_THREAD_AS. A member of a struct that is NOT internally synchronised and is
// handed between threads at known points (a prefetch worker fills it, the joiner reads it after the join):
//
//     struct GrepScanPhases { …; [[no_unique_address]] Diagnostics::ThreadOwner threadOwner; };
//
// Debug: an atomic id, claimed by the first thread that asserts on the object. release() hands the object on; the
// next assert claims it again. Release: an EMPTY class under [[no_unique_address]], so the struct's size and layout
// are byte-identical to the struct without the member — a hot SoA/POD struct's `static_assert( sizeof( X ) == N )`
// holds in release unchanged. In debug the member is 8 bytes, which is why it belongs on coordinating objects (an
// index, a worker's result slot, a server's session state), never on a per-node or per-edge record.
//
// A copy is a NEW object and starts unclaimed; assignment keeps the destination's claim. Both builds must never be
// mixed in one link: the layout differs, which is the sizeof hazard CLAUDE.md documents. The debug constructors CALL
// debugFlavourLinkCheck(), which only a debug diagnostics.cpp defines, so a debug TU linked against a release
// diagnostics.cpp fails to LINK instead of running with two layouts (measured: an inline `&symbol` reference is folded
// away and links; a call is not). The check is one-sided on purpose: the release class stays EMPTY and TRIVIAL, because
// a release struct's triviality is part of the layout promise.
#if !defined( NDEBUG )
void debugFlavourLinkCheck() noexcept;
class ThreadOwner
{
public:
    ThreadOwner() noexcept { debugFlavourLinkCheck(); }
    ThreadOwner( const ThreadOwner& ) noexcept { debugFlavourLinkCheck(); }   // a copy is a new object: unclaimed
    ThreadOwner& operator=( const ThreadOwner& ) noexcept { return *this; }

    void release() noexcept { ownerId.store( 0, std::memory_order_relaxed ); }

    // true when the calling thread owns the object (claiming it if nobody did); on false `*owner` names the owner
    bool claimOrCheck( std::uint64_t* owner ) noexcept
    {
        const std::uint64_t self = currentThreadId();
        std::uint64_t       seen = ownerId.load( std::memory_order_relaxed );
        if( seen == self )
        {
            return true;
        }
        if( seen == 0 && ownerId.compare_exchange_strong( seen, self, std::memory_order_relaxed ) )
        {
            return true;
        }
        *owner = seen;
        return seen == self;
    }

private:
    std::atomic<std::uint64_t> ownerId{ 0 };
};
#else
class ThreadOwner
{
public:
    void release() noexcept {}
};
#endif

namespace detail
{
// VALIDATE's two outcomes. Both are [[nodiscard]] calls, so a discarded VALIDATE( … ) — the `?:` that joins them —
// warns on clang (-Wunused-result on both arms) and gcc (-Wunused-result): the macro is only legal inside a condition.
[[nodiscard]] inline constexpr bool validatePassed() noexcept
{
    return true;
}

#if !defined( NDEBUG )
// One instantiation per VALIDATE site: `Site` is the type of a `[] {}` written in the macro, and every lambda-expression
// has its own type, so `seen` is a per-site latch without __COUNTER__ (which is per-TU and would merge unrelated sites).
template<class Site>
[[nodiscard, gnu::cold, gnu::noinline]] bool validateFailed( Site, const char* expr, const char* file, int line, const char* function,
                                                            const char* description ) noexcept
{
    static ::std::atomic<bool> seen{ false };
    if( !seen.exchange( true, ::std::memory_order_relaxed ) )
    {
        ConsoleLog::handleValidateFailed( expr, file, line, function, description );
    }
    return false;
}
#else
[[nodiscard]] inline constexpr bool validateFailed( decltype( sizeof( 0 ) ) /*messageBytes*/ ) noexcept
{
    return false;
}
#endif
} // namespace detail
} // namespace Diagnostics

// --------------------------------------------------------------------------------------------------------------------
// 3. ASSUME / EXPECTS / ENSURES / DASSERT / UNREACHABLE
//
// ONE variadic spelling per word: `ASSUME( e )` or `ASSUME( e, "why this holds" )`. There is no _TEXT twin. The
// message is pasted after an empty literal ("" msg), so it must be a string literal in EVERY build — a variable, or
// the right-hand half of an expression whose top-level comma split it (`ASSUME( f<a, b>( x ) )`), does not compile.
// An expression with a top-level comma still needs its own parentheses, exactly as before.
// --------------------------------------------------------------------------------------------------------------------
#if !defined( NDEBUG )

  #define RW_CHECK_( kind, e, msg )                                                                                       \
      do                                                                                                                 \
      {                                                                                                                  \
          if( !static_cast<bool>( e ) ) [[unlikely]]                                                                     \
          {                                                                                                              \
              ::Diagnostics::ConsoleLog::handleAssert( kind, #e, _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg );     \
          }                                                                                                              \
      } while( 0 )

  #define RW_ASSUME_( kind, e, msg )  RW_CHECK_( kind, e, msg )
  #define RW_DASSERT_( e, msg )       RW_CHECK_( ::Diagnostics::CheckKind::DAssert, e, msg )
  #define RW_UNREACHABLE_( msg )                                                                                          \
      ( ::Diagnostics::ConsoleLog::handleAssert( ::Diagnostics::CheckKind::Unreachable, "UNREACHABLE()", _SHORTERFILE_, __LINE__, \
                                                 __PRETTY_FUNCTION__, msg ),                                              \
        __builtin_trap() )

#else   // NDEBUG — release build

  // The release form of an assumption, per front end. None of them evaluates `e`.
  #if defined( __clang__ )
    // __builtin_assume: the expression is never evaluated. Clang DISCARDS an assumption whose expression may have side
    // effects — any call it cannot see through, and any inline asm (fastmath::isFiniteFast carries a load-bearing
    // barrier to survive -ffast-math) — and warns -Wassume. Discarding is the safe outcome and the warning is cosmetic,
    // so it is silenced at this one expansion site.
    #define RW_ASSUME_RELEASE_( e )                                                                                       \
        _Pragma( "clang diagnostic push" )                                                                               \
        _Pragma( "clang diagnostic ignored \"-Wassume\"" )                                                               \
        __builtin_assume( static_cast<bool>( e ) );                                                                      \
        _Pragma( "clang diagnostic pop" )
  #else
    #if defined( __has_cpp_attribute )
      #if __has_cpp_attribute( assume ) >= 202207L
        #define RW_HAS_ASSUME_ATTRIBUTE_ 1
      #endif
    #endif
    #if defined( RW_HAS_ASSUME_ATTRIBUTE_ )
      // C++23 [[assume]] (GCC 13+): the expression is not evaluated, and GCC outlines it for value-range facts only.
      // The previous GCC form, `if( !e ) __builtin_unreachable()`, EVALUATES any call it cannot prove pure — every
      // ASSUME( verifyCsr( … ) )-shaped predicate ran in the shipped gcc build (bench/PROFILE.md records one).
      #define RW_ASSUME_RELEASE_( e ) [[assume( static_cast<bool>( e ) )]];
    #else
      // A front end with neither: the pre-C++23 idiom. It DOES evaluate a call the optimizer cannot prove pure.
      #define RW_ASSUME_RELEASE_( e )                                                                                     \
          if( !static_cast<bool>( e ) )                                                                                  \
          {                                                                                                              \
              __builtin_unreachable();                                                                                   \
          }
    #endif
  #endif

  // `sizeof( msg )` keeps the literal requirement in release without emitting anything.
  #define RW_ASSUME_( kind, e, msg )                                                                                      \
      do                                                                                                                 \
      {                                                                                                                  \
          static_cast<void>( sizeof( msg ) );                                                                            \
          RW_ASSUME_RELEASE_( e )                                                                                        \
      } while( 0 )

  // Nothing at run time and no promise; the operand stays compiled (unevaluated) so a release-only break cannot hide
  // and a variable read only by a DASSERT is not an unused-variable warning.
  #define RW_DASSERT_( e, msg )                                                                                           \
      do                                                                                                                 \
      {                                                                                                                  \
          static_cast<void>( sizeof( msg ) );                                                                            \
          static_cast<void>( sizeof( static_cast<bool>( e ) ) );                                                         \
      } while( 0 )

  // std::unreachable() is exactly this builtin in libc++ and libstdc++; <utility> is not included because this header
  // must stay library-free (test/noaliascheck.sh arm 5: libc++'s own headers do not compile under its forced shape).
  #define RW_UNREACHABLE_( msg ) ( static_cast<void>( sizeof( msg ) ), __builtin_unreachable() )

#endif

#define ASSUME( e, ... )     RW_ASSUME_( ::Diagnostics::CheckKind::Assume, e, "" __VA_OPT__( __VA_ARGS__ ) )
#define EXPECTS( e, ... )    RW_ASSUME_( ::Diagnostics::CheckKind::Expects, e, "" __VA_OPT__( __VA_ARGS__ ) )
#define ENSURES( e, ... )    RW_ASSUME_( ::Diagnostics::CheckKind::Ensures, e, "" __VA_OPT__( __VA_ARGS__ ) )
#define DASSERT( e, ... )    RW_DASSERT_( e, "" __VA_OPT__( __VA_ARGS__ ) )
#define UNREACHABLE( ... )   RW_UNREACHABLE_( "" __VA_OPT__( __VA_ARGS__ ) )

// DASSERT — the same check as ASSUME in debug, and NOTHING in release: no code, and no promise either. Use it where the
// predicate is worth checking but the release-mode assumption would be worth more than it is true: a floating-point
// identity (an assumption the optimizer may act on in the one translation unit whose contract is reproducible
// arithmetic, pagerank.cpp), or an internal structural invariant whose corruption is not impossible — the mid-build
// struct-size hazard CLAUDE.md documents (half the objects compiled against one layout of a host record, half against
// another) produces exactly a corrupt CSR, and under a plain ASSUME the bounds reasoning that would have caught it has
// already been optimized away on the strength of the promise. ASSUME stays the default: a precondition this code
// GUARANTEES is worth stating to the optimizer. DASSERT is for the ones it does not.

// --------------------------------------------------------------------------------------------------------------------
// 3b. VALIDATE — external input, evaluated in EVERY build, never assumed
//
//     if( !VALIDATE( isBareCommitSha( scope.baselineSha ) ) ) { … refuse or degrade … }
//
// The expression is evaluated exactly once, in the enclosing scope (no capture, `this` and structured bindings work).
// Release cost: the compare itself, weighted likely-true at the call site. Debug adds a one-line trace the first time
// a site sees false. The result is [[nodiscard]]: VALIDATE belongs in an if / while / return / && / || condition, and
// test/selfcheckcheck.sh arm (E) refuses it anywhere else.
// --------------------------------------------------------------------------------------------------------------------
#if !defined( NDEBUG )
  #define RW_VALIDATE_FAILED_( e, msg )                                                                                   \
      ::Diagnostics::detail::validateFailed( [] {}, #e, _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg )
#else
  #define RW_VALIDATE_FAILED_( e, msg ) ::Diagnostics::detail::validateFailed( sizeof( msg ) )
#endif
#define VALIDATE( e, ... )                                                                                                \
    ( __builtin_expect( static_cast<bool>( e ), 1 ) ? ::Diagnostics::detail::validatePassed()                             \
                                                    : RW_VALIDATE_FAILED_( e, "" __VA_OPT__( __VA_ARGS__ ) ) )

// --------------------------------------------------------------------------------------------------------------------
// 3c. ASSUME_SAME_THREAD / ASSUME_SAME_THREAD_AS — single-thread ownership, checked in debug
//
// ASSUME_SAME_THREAD( ["msg"] ) — this SITE is only ever reached from ONE thread for the life of the process. The
// first thread to hit it claims it (a static per-site atomic latch); a later hit from any other thread reports and
// traps. Right for process singletons touched from one thread only: the MCP server's cached index and workspace
// registry, which the request loop owns and the detached qsnap prefetch worker must never touch.
// WRONG for code that a pool runs on many threads over DIFFERENT objects (a parse-pool worker, a parallel-for body):
// the site is legitimately reached from every worker, and the latch would fire on the second one. Use the per-object
// form there.
//
// ASSUME_SAME_THREAD_AS( obj[, "msg"] ) — OBJECT `obj` is only touched by its owning thread. `obj.threadOwner` is a
// Diagnostics::ThreadOwner member (see §2). Hand-offs are explicit: the thread giving the object up calls
// `obj.threadOwner.release()`, and the next assert claims it.
//
// Both compile to nothing in release. They complement ThreadSanitizer rather than duplicate it: TSan finds races that
// HAPPEN, in a separate build CI does not run, at 5-15x cost; these find a broken OWNERSHIP CONTRACT the first time
// the wrong thread arrives, in every plain and asan CI leg, even when the two accesses never overlap in that run —
// and they write the contract down at the site.
// --------------------------------------------------------------------------------------------------------------------
#if !defined( NDEBUG )
  #define RW_SAME_THREAD_( msg )                                                                                          \
      do                                                                                                                 \
      {                                                                                                                  \
          static ::std::atomic<::std::uint64_t> rwSiteOwner_{ 0 };                                                       \
          const ::std::uint64_t                 rwSelf_ = ::Diagnostics::currentThreadId();                              \
          ::std::uint64_t                       rwSeen_ = rwSiteOwner_.load( ::std::memory_order_relaxed );              \
          if( rwSeen_ != rwSelf_ ) [[unlikely]]                                                                          \
          {                                                                                                              \
              if( rwSeen_ != 0 || !rwSiteOwner_.compare_exchange_strong( rwSeen_, rwSelf_, ::std::memory_order_relaxed ) ) \
              {                                                                                                          \
                  if( rwSeen_ != rwSelf_ )                                                                               \
                  {                                                                                                      \
                      ::Diagnostics::ConsoleLog::handleThreadViolation( rwSeen_, rwSelf_, _SHORTERFILE_, __LINE__,       \
                                                                        __PRETTY_FUNCTION__, msg );                      \
                  }                                                                                                      \
              }                                                                                                          \
          }                                                                                                              \
      } while( 0 )
  #define RW_SAME_THREAD_AS_( obj, msg )                                                                                  \
      do                                                                                                                 \
      {                                                                                                                  \
          ::std::uint64_t rwOwner_ = 0;                                                                                  \
          if( !( obj ).threadOwner.claimOrCheck( &rwOwner_ ) ) [[unlikely]]                                              \
          {                                                                                                              \
              ::Diagnostics::ConsoleLog::handleThreadViolation( rwOwner_, ::Diagnostics::currentThreadId(), _SHORTERFILE_, \
                                                                __LINE__, __PRETTY_FUNCTION__, msg );                    \
          }                                                                                                              \
      } while( 0 )
#else
  #define RW_SAME_THREAD_( msg )          do { static_cast<void>( sizeof( msg ) ); } while( 0 )
  #define RW_SAME_THREAD_AS_( obj, msg )  do { static_cast<void>( sizeof( msg ) ); static_cast<void>( sizeof( ( obj ).threadOwner ) ); } while( 0 )
#endif
#define ASSUME_SAME_THREAD( ... )          RW_SAME_THREAD_( "" __VA_OPT__( __VA_ARGS__ ) )
#define ASSUME_SAME_THREAD_AS( obj, ... )  RW_SAME_THREAD_AS_( obj, "" __VA_OPT__( __VA_ARGS__ ) )

// --------------------------------------------------------------------------------------------------------------------
// 4. PANIC — always active, never compiled out
// --------------------------------------------------------------------------------------------------------------------
#define PANIC( msg ) ::Diagnostics::ConsoleLog::handlePanic( _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, msg )

// --------------------------------------------------------------------------------------------------------------------
// 4b. DISCLOSE — a degrade path the reader must learn about
//
// For rung-2 sites of the error ladder (a recoverable runtime condition): the code clamps / falls back and CONTINUES,
// and the reader of the answer must be able to tell. docs/ARCHITECTURE.md: "A disclosure that lives only in an
// assertion is a disclosure that does not ship." One name, three arities, dispatched on the argument count:
//
//   DISCLOSE( sink, why )          sink.disclose( why ) in EVERY build, then a debug trace named by the two arguments
//   DISCLOSE( sink, why, "msg" )   sink.disclose( why ) in EVERY build, then a debug trace with the literal message
//   DISCLOSE( msg )                a debug trace ONLY — see "THE ONE-ARGUMENT FORM" below before using it
//
// THE SINK is the object whose field the emitter ALREADY reads for this answer — a reference lookup → ok="0"
// v="unknown", a grep collector → hits_capped= / counts_floor=, a parse result's health rows → why= / unindexed=, a
// root's est_tokens measurement → an omitted est_tokens=, a sidecar read → its symlinkRefused. It models Diagnostics::DisclosureSink,
// which is checked at COMPILE TIME at every site:
//     struct GrepCollection {
//         enum class DisclosureWhy : std::uint8_t { RegexError, UnreadableFile };   // owned by the sink, scoped
//         void disclose( DisclosureWhy why ) noexcept;                               // sets the field the emitter reads
//     };
//     DISCLOSE( found, GrepCollection::DisclosureWhy::UnreadableFile );
// A sink that is not a model fails with this header's own message; a `why` of another type, or one computed at run
// time, does not compile either: the macro binds it to a `constexpr` of the sink's DisclosureWhy.
//
// WHY `why` IS A SCOPED ENUM OWNED BY THE SINK (and not a string): it is the cheapest type that forbids a run-time
// string outright (one byte, no allocation, no formatting on or off the degrade path); the set of reasons a sink can
// emit is closed and visible in one declaration, so a `switch` over it inside disclose() gets -Wswitch's exhaustiveness
// check when a reason is added; and a later central vocabulary is the union of these enums, a mechanical move. A scoped
// enum is required (an unscoped one would accept a bare integer through promotion).
//
// Diagnostics::answerUnchanged — THE EXPLICIT "THIS DEGRADE CANNOT CHANGE THE ANSWER" SINK. Its `why` is a non-empty
// string LITERAL: the reason, read by people. It sets nothing, so it is legitimate only when the degrade changes the
// COST of the answer and never its CONTENT. Measured on the 195 degrade sites this header's rename touched, 30 are that
// kind, in four shapes:
//   - a cache that is REJECTED and rebuilt from source (format version, parser version, arch, checksum, torn record,
//     path-hash collision): this run parses from source and answers byte-identically;
//   - a cache WRITE that failed (the git-oracle history cache, saveCache's temp / short-write / rename, a non-regular
//     cache path): this answer is already computed; only the next run is cold;
//   - a performance fallback that computes the same bytes (per-spec query walks instead of the grouped walk, the grep
//     prefetch recomputed inline, an FS watcher that falls back to the full stat sweep);
//   - a lock that could not be taken where a re-check still refuses a stale write (the edit lock).
// NOT legitimate — pass a real sink instead:
//   - anything that drops, truncates, caps or guesses rows, or leaves a count short;
//   - a cache write that STORES partial facts a later run will reuse — that changes the NEXT answer (the prewarm miss
//     and the parse pool's partial file do exactly this);
//   - a refusal (it already exits non-zero and says why);
//   - a guard that cannot fire (five of the 30 were: delete the guard, do not decorate it).
// There is no pin on these sites; test/selfcheckcheck.sh arm (U) LISTS every one with its reason on every run, and
// refuses one whose reason is not a non-empty literal.
//
// Diagnostics::answerRefused — THE EXPLICIT "THIS DEGRADE REFUSES THE ANSWER" SINK, the one shape answerUnchanged may not
// take. Its `why` is the same kind of non-empty string LITERAL, and it sets nothing, because the disclosure is the refusal
// itself: legitimate ONLY where the same path, in EVERY build, emits NO answer and says why where the caller will read it —
// a non-zero exit with the cause on stderr, an MCP error result, a query's named failure. NOT legitimate where any part of
// an answer is still printed (that answer needs a real sink), or where the only message is this trace. Arm (U) lists these
// sites too, apart from the answerUnchanged ones.
//
// THE ONE-ARGUMENT FORM, `DISCLOSE( msg )`, DISCLOSES NOTHING TO THE USER OF THE RELEASE BINARY. It is the pre-0.6.2
// degraded-path alert under a new name, byte for byte: in debug one "[math degraded]" line per call site on stderr,
// under NDEBUG (every shipped build) nothing at all. It exists so the rename could be mechanical; each of those sites
// is converted to a sink form by the degrade-disclosure lane. Until then it is honest ONLY where the same code path also
// sets the output field the emitter reads. test/selfcheckcheck.sh arm (R) counts one-argument sites — sink forms never
// count — and lets the number only go DOWN; at 0 the one-argument form becomes a refusal.
//
// The dispatch counts top-level arguments with __VA_OPT__: a string literal's commas are inside one token; a sink
// expression with a top-level comma needs its own parentheses, as any macro argument does.
//
// Never write ASSUME( false ) on a degrade path: in release that is an assumption of false, the optimizer deletes the
// fallback behind it and reaching the function becomes undefined behaviour (CLAUDE.md non-negotiable #4; gate arm D).
// --------------------------------------------------------------------------------------------------------------------
namespace Diagnostics
{
namespace detail
{
// Library-free spellings of what the concept needs (<concepts> / <type_traits> would break noaliascheck arm 5's
// forced-shape compile, and both GCC and Clang ship __is_enum as a built-in trait).
template<class T> struct NoRef { using type = T; };
template<class T> struct NoRef<T&> { using type = T; };
template<class T> struct NoRef<T&&> { using type = T; };
template<class A, class B> inline constexpr bool isSame = false;
template<class A> inline constexpr bool isSame<A, A> = true;
template<class A, class B> concept SameAs = isSame<A, B> && isSame<B, A>;
template<class W> concept ScopedEnum = ( __is_enum( W ) ) && !requires( W w ) { +w; };   // an unscoped enum promotes
} // namespace detail

struct AnswerUnchanged
{
    // The reason: a non-empty string literal, bound at compile time (DISCLOSE makes it a constexpr), never built at run time.
    class DisclosureWhy
    {
    public:
        template<decltype( sizeof( 0 ) ) N>
        constexpr DisclosureWhy( const char( &literal )[N] ) noexcept : reason( literal )
        {
            static_assert( N > 1, "Diagnostics::answerUnchanged / answerRefused needs a non-empty literal reason: say why this degrade cannot change the answer, or how the answer is refused" );
        }
        constexpr const char* text() const noexcept { return reason; }

    private:
        const char* reason;
    };

    constexpr void disclose( DisclosureWhy ) const noexcept {}
};
inline constexpr AnswerUnchanged answerUnchanged{};

struct AnswerRefused
{
    using DisclosureWhy = AnswerUnchanged::DisclosureWhy;   // the same literal-reason type: a reason a person reads
    constexpr void disclose( DisclosureWhy ) const noexcept {}
};
inline constexpr AnswerRefused answerRefused{};

// The sink contract DISCLOSE( sink, why ) checks at compile time: a nested DisclosureWhy — a scoped enum (or
// answerUnchanged's / answerRefused's literal reason) — and `void disclose( DisclosureWhy ) noexcept` callable on the sink as written.
template<class S>
concept DisclosureSink =
    requires { typename detail::Bare<S>::DisclosureWhy; }
    && ( detail::ScopedEnum<typename detail::Bare<S>::DisclosureWhy> || detail::isSame<detail::Bare<S>, AnswerUnchanged>
         || detail::isSame<detail::Bare<S>, AnswerRefused> )
    && requires( typename detail::NoRef<S>::type& sink, const typename detail::Bare<S>::DisclosureWhy why ) {
           { sink.disclose( why ) } noexcept -> detail::SameAs<void>;
       };

namespace detail
{
struct NotADisclosureSink;   // incomplete on purpose: a non-sink's `why` cannot be bound to anything
template<class S> struct WhyOfImpl { using type = NotADisclosureSink; };
template<class S>
    requires requires { typename S::DisclosureWhy; }
struct WhyOfImpl<S> { using type = const typename S::DisclosureWhy; };
template<class S> using WhyOf = typename WhyOfImpl<Bare<S>>::type;
} // namespace detail
} // namespace Diagnostics

#define DISCLOSE( ... )                RW_DISCLOSE_PASTE_( RW_DISCLOSE_, RW_DISCLOSE_ARGC_( __VA_ARGS__ ) )( __VA_ARGS__ )
#define RW_DISCLOSE_ARGC_( ... )       RW_DISCLOSE_ARGC_PICK_( __VA_ARGS__ __VA_OPT__( , ) 3, 2, 1, 0 )
#define RW_DISCLOSE_ARGC_PICK_( a, b, c, n, ... ) n
#define RW_DISCLOSE_PASTE_( a, b )     RW_DISCLOSE_PASTE2_( a, b )
#define RW_DISCLOSE_PASTE2_( a, b )    a##b

#if !defined( NDEBUG )
  #define RW_DISCLOSE_TRACE_( text )                                                                                      \
      do                                                                                                                 \
      {                                                                                                                  \
          static ::std::atomic<bool> rwDegradeSeen_{ false };                                                            \
          if( !rwDegradeSeen_.exchange( true, ::std::memory_order_relaxed ) )                                            \
          {                                                                                                              \
              ::Diagnostics::ConsoleLog::handleDegraded( _SHORTERFILE_, __LINE__, __PRETTY_FUNCTION__, text );           \
          }                                                                                                              \
      } while( 0 )
#else
  #define RW_DISCLOSE_TRACE_( text ) do { } while( 0 )   // the old alert's release expansion, unchanged: the trace ships nothing
#endif

#define RW_DISCLOSE_SINK_( sink, why, text )                                                                              \
    do                                                                                                                   \
    {                                                                                                                    \
        static_assert( ::Diagnostics::DisclosureSink<decltype( sink )>,                                                  \
                       "DISCLOSE( sink, why ): the sink does not model Diagnostics::DisclosureSink — it needs a nested scoped enum DisclosureWhy and void disclose( DisclosureWhy ) noexcept" ); \
        constexpr ::Diagnostics::detail::WhyOf<decltype( sink )> rwDisclosureWhy_ = why;                                 \
        ( sink ).disclose( rwDisclosureWhy_ );                                                                           \
        static_cast<void>( sizeof( text ) );   /* keeps "msg" a literal in release too, where the trace is compiled out */ \
        RW_DISCLOSE_TRACE_( text );                                                                                      \
    } while( 0 )

#define RW_DISCLOSE_0()                                                                                                   \
    do { static_assert( false, "DISCLOSE needs a sink and a reason: DISCLOSE( sink, Sink::DisclosureWhy::X[, \"msg\"] )" ); } while( 0 )
#define RW_DISCLOSE_1( msg )             RW_DISCLOSE_TRACE_( msg )
#define RW_DISCLOSE_2( sink, why )       RW_DISCLOSE_SINK_( sink, why, #sink " <- " #why )
#define RW_DISCLOSE_3( sink, why, msg )  RW_DISCLOSE_SINK_( sink, why, "" msg )

// --------------------------------------------------------------------------------------------------------------------
// 6. ASSUME_NO_ALIAS — a debug check AND a release optimizer fact
//
// Use in functions that WRITE through one reference while READING another of the same type, where passing the same
// object twice would silently produce a wrong result (an out-parameter read mid-computation, a destination that is
// also an input).
//
// Debug:   ASSUME fires if a and b are the same object (exact address equality — it does NOT catch partial overlap).
// Release: the ASSUME is an inert __builtin_assume that alias analysis never reads (measured 2026-09-12: codegen
//          byte-identical to no macro at all). RW_ASSUME_SEPARATE_STORAGE is the part that does the work — it lowers
//          to `llvm.assume [ "separate_storage"(a, b) ]`, which BasicAA consumes, so the codegen matches `__restrict__`
//          on the parameters exactly. Measured at -O2 -DNDEBUG, instructions:
//              `out=a; out+=b; out+=a;`  arm64 10 -> 6, x86-64 11 -> 9
//              `dst[i] += k*src[i]` loop  arm64 62 -> 56, x86-64 68 -> 45
//          (the loop delta is the runtime overlap check plus the scalar fallback loop LLVM emits when it cannot prove
//          dst and src disjoint). On a compiler without __builtin_assume_separate_storage (GCC, clang < 17) the
//          assumption is `( (void)0 )` and the debug check still runs. BasicAA reads the bundle only when its
//          `basic-aa-separate-storage` option is on: off by default in LLVM 17 (AppleClang 16 / Xcode 16.2), on from
//          LLVM 18. CMakeLists.txt passes `-mllvm -basic-aa-separate-storage` to our targets whenever the compiler
//          accepts it, so LLVM 17 consumes the promise too (a no-op on 18+; test/noaliascheck.sh arm 8 is the `=false`
//          control). Even with the option on, LLVM 17 consults the hint only at the assume's own context, which the
//          loop vectorizer's alias queries never carry (llvm/llvm-project#64666, fixed in LLVM 18 by #76770): on
//          AppleClang 16 the promise removes scalar reloads but leaves a loop's runtime overlap check in place. The
//          gate classifies that loop path separately (LOOP_CONSUMED / LOOP_NOT_CONSUMED).
//
// THE CONTRACT (clang/docs/LanguageExtensions.rst, release/19.x): the arguments "are assumed to point into separately
// allocated storage (either different variable definitions or different dynamic storage allocations) … 'storage' here
// refers to the outermost enclosing allocation of any particular object (so for example, it's never correct to call
// this function passing the addresses of fields in the same struct, elements of the same array, etc.)". LangRef: "no
// pointer based on one of its arguments can alias any pointer based on the other." Two elements of one array or two
// members of one struct are a LIE and undefined behaviour in release; the debug check cannot see it.
//
// TWO CONTAINERS need the _BUF form. `separate_storage( &dst, &src )` on two std::vector references says the 24-byte
// headers are separate; the loop body indexes the HEAP BUFFERS, reached through the begin_ pointers loaded from those
// headers, and the optimizer cannot infer buffer separation from header separation (measured: the object form leaves
// the loop at 65/65, the .data() form drops it to 61 arm64 / 41 x86-64). ASSUME_NO_ALIAS_BUF checks the OBJECTS (two
// live containers never share an allocation) and promises the BUFFERS. Empty containers are fine: nothing is ever
// accessed through a null data(), so the promise is vacuous there — the bundle is read only by alias queries, which
// need an access to ask about, and LLVM does not fold `p == q` from it (measured at -O3: the compare survives and
// answers true for two empty vectors). The two forms that would avoid the null — promising the object address when
// empty, or a branch around the builtin — both lose the whole loop effect (arm64 66/66 vs 61, x86-64 66/65 vs 41), so
// the plain .data() form stays; test/noaliascheck.sh arm 7 runs the release probe on two empty vectors. If the
// function already has a "nothing to do" early return on empty input, put the macro AFTER it: the promise then runs on
// non-null buffers and still dominates the loop (measured: 64 vs 61 arm64, 44 vs 41 x86-64 — the difference is the
// emptiness test itself, which costs the same without the promise). Do not add an early return for the macro's sake;
// the one line alone is the full effect.
//
// OWNING CONTAINERS ONLY: std::vector, std::string, std::array — anything whose .data() is its own allocation (or lies
// inside the object itself, as std::array's and a short std::string's do; two distinct objects are two allocations
// either way). NEVER a view: two std::span or std::string_view objects can look into ONE allocation, and the promise
// is per allocation, so even two non-overlapping views would be a lie the release build acts on while the object check
// passes. The macro refuses views at compile time (static_assert on Diagnostics::detail::isView); for a pair of views,
// promise the OWNERS they came from, or use ASSUME_NO_ALIAS on the views (the object check alone) and accept that the
// loop keeps its overlap check.
//
// WHY NOT `__restrict` ON THE SIGNATURE. Prefer this macro in the body: it is checked in debug, it is the same
// optimizer fact in release, and it does not change the API. If a signature ever does need the qualifier,
// `__restrict__` (double underscore BOTH sides) is the only spelling allowed in this tree. On macOS <sys/cdefs.h> does
//     #if __STDC_VERSION__ < 199901
//     #define __restrict
//     #endif
// and __STDC_VERSION__ is undefined in C++, so every bare `__restrict` that follows any libc/libc++ include is silently
// deleted — verified by bisect: a function lost its noalias IR attributes the moment <cstdio> was included.
// `__restrict__` is a keyword and survives. test/noaliascheck.sh arm 4 sweeps src/ for the bare spelling.
//
//   void crossProduct( const Vec& a, const Vec& b, Vec& out ) {
//       ASSUME_NO_ALIAS( a, out );        // inputs are only read, so the contract is each input against the output
//       ASSUME_NO_ALIAS( b, out );
//       ...
//   }
//   void waterFill( const std::vector<uint32_t>& demand, std::vector<uint32_t>& alloc ) {
//       ASSUME_NO_ALIAS_BUF( demand, alloc );   // the two BUFFERS are separate storage
//       ...
//   }
// --------------------------------------------------------------------------------------------------------------------
#if defined( __has_builtin )
  #if __has_builtin( __builtin_assume_separate_storage )
    #define RW_ASSUME_SEPARATE_STORAGE( p, q ) __builtin_assume_separate_storage( ( p ), ( q ) )
  #endif
#endif
#if !defined( RW_ASSUME_SEPARATE_STORAGE )
  #define RW_ASSUME_SEPARATE_STORAGE( p, q ) ( (void)0 )   // GCC / clang < 17: no equivalent; the debug check still runs
#endif

#define ASSUME_NO_ALIAS( a, b )                                                                                           \
    do                                                                                                                   \
    {                                                                                                                    \
        ASSUME( static_cast<const void*>( &( a ) ) != static_cast<const void*>( &( b ) ),                                \
                "aliasing violation: '" #a "' and '" #b "' are the same object" );                                        \
        RW_ASSUME_SEPARATE_STORAGE( &( a ), &( b ) );                                                                    \
    } while( 0 )

// Three-way variant for functions with three outputs (buildPathTable's rowFileIds / outUniqueFiles / outRowPathIdx).
#define ASSUME_NO_ALIAS3( a, b, c )                                                                                       \
    do                                                                                                                   \
    {                                                                                                                    \
        ASSUME_NO_ALIAS( a, b );                                                                                         \
        ASSUME_NO_ALIAS( a, c );                                                                                         \
        ASSUME_NO_ALIAS( b, c );                                                                                         \
    } while( 0 )

// Two containers: the OBJECTS must be distinct (checked), and the fact the loop needs is that their BUFFERS are
// separate storage (promised via .data()).
#define ASSUME_NO_ALIAS_BUF( a, b )                                                                                       \
    do                                                                                                                   \
    {                                                                                                                    \
        static_assert( !::Diagnostics::detail::isView<decltype( a )> && !::Diagnostics::detail::isView<decltype( b )>,  \
                       "ASSUME_NO_ALIAS_BUF: a view (std::span / std::string_view) can share one allocation with another view; promise the owning containers instead" ); \
        ASSUME( static_cast<const void*>( &( a ) ) != static_cast<const void*>( &( b ) ),                                \
                "aliasing violation: '" #a "' and '" #b "' are the same container" );                                     \
        RW_ASSUME_SEPARATE_STORAGE( ( a ).data(), ( b ).data() );                                                        \
    } while( 0 )

// --------------------------------------------------------------------------------------------------------------------
// 7. Benchmark micro-helpers — DoNotOptimize / ClobberMemory
//
// The two canonical Google-Benchmark primitives, reimplemented here so micro-benchmarks in this tree (bench/*.cpp) do
// not need the full benchmark library. Both are pure COMPILER barriers (empty inline asm) — they emit no instructions.
//
//   DoNotOptimize(x) : forces `x` to be materialised, so the compiler cannot delete the computation that produced it
//                      (defeats dead-code elimination of a benchmarked result).
//
//   ClobberMemory()  : a full compiler read/write memory barrier. Forces all pending stores to be committed to memory
//                      and stops the compiler from caching or reordering memory accesses across this point. Use it
//                      after a step that writes through a buffer (a radix pass filling its scratch array, a CSR build
//                      filling colIndices[]) so the writes can't be hoisted into registers or elided.
//
// IMPORTANT: ClobberMemory is a *compiler* barrier only. It does NOT flush CPU caches, evict working sets, or simulate
// memory pressure from other processes. To model a cold-cache cost you must actually touch a large foreign buffer
// between iterations — these helpers won't do that for you.
// --------------------------------------------------------------------------------------------------------------------
namespace Diagnostics
{

#if defined( __GNUC__ ) || defined( __clang__ )

template<typename T>
[[gnu::always_inline]] inline void DoNotOptimize( const T& value ) noexcept
{
    asm volatile( "" : : "r,m"(value) : "memory" );
}

template<typename T>
[[gnu::always_inline]] inline void DoNotOptimize( T& value ) noexcept
{
  #if defined( __clang__ )
    asm volatile( "" : "+r,m"(value) : : "memory" );
  #else
    asm volatile( "" : "+m,r"(value) : : "memory" );
  #endif
}

[[gnu::always_inline]] inline void ClobberMemory() noexcept
{
    asm volatile( "" : : : "memory" );
}

#else   // portable fallback (no inline asm): a volatile sink + atomic fence

template<typename T>
inline void DoNotOptimize( const T& value ) noexcept
{
    volatile const T* p = &value;
    (void)p;
}
template<typename T>
inline void DoNotOptimize( T& value ) noexcept
{
    volatile T* p = &value;
    (void)*p;
}
inline void ClobberMemory() noexcept
{
    // No inline-asm barrier available; best effort. (Unused on Clang/GCC.)
    static volatile int barrier = 0;
    barrier = barrier;
}

#endif

} // namespace Diagnostics
