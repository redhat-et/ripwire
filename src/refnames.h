#pragma once
// refnames.h — MEM-REF-SHRINK step 2: the reference rows' NAME texts (Reference::calleeName / qualifier / recvVar, RawRef::name /
// qualifier / recvVar) as rw::InternedText, a 4 B id into ONE process-wide text pool (infra/internedtext.h), instead of a 24 B
// (libc++) / 32 B (libstdc++) std::string header each. Step 1's Stage 0 counts (reports/mem-ref-shrink.md): 59-116 K distinct callee
// names over 1.2-2.0 M references on envoy / cockroach / vscode, and two row copies are live at the parse-pool peak, so the header
// bytes, not the text, were the cost.
//
// WHY ONE POOL, NOT PER-THREAD TABLES REMAPPED AT MERGE. Most readers hold only a `const Reference&` (no IngestResult, no table), and
// the parse workers both write and READ their RawRefs' names while they extract (erase_if passes, suffix tests, re-splits). A
// per-thread table would need a thread-local "current table" for every one of those reads, a remap pass over every row at the
// parse-pool join, a second one for cache-hit rows, and a rule for rows copied between results. One shared pool needs none.
//
// NEVER DESTROYED. The pool is held in rw::NoDestroy: a detached thread (mcpindex.h maybePrefetchHeadSnapshot's head-snapshot
// ingest) can still be interning when main returns, so a pool freed by static destruction would be a use-after-free at exit
// (test/textpoolcheck.sh arm H). It is constant-initialised (RW_REF_CONSTINIT below), so no dynamic initialiser can intern first.
//
// BINDINGS TOO (MEM-B1 BIND-INTERN). Binding::var / importedName / typeName and RawBind's three share this pool: 36 B rows instead
// of 96 (libc++), ~1.7 M bindings on vscode. Every binding text is a name, a written type or module path, or a fixed mark
// (kFnBindLambdaTarget, kPythonFromMemberMark, the `?` / `~` / `?:` prefixes on a name): none is keyed by a position, so a server's
// re-index adds only names it has not seen.
//
// GROWTH. The pool keeps every distinct name it has seen and never frees one, so a long-running server (--mcp / --listen / --lsp)
// grows with the distinct names of the trees it re-indexes: about 3 MB of string headers per 100 K names. No pooled field is keyed
// by a POSITION: a registrar Value row's object-literal offset, once a "@<byte offset>" tail on its qualifier, is the numeric
// Reference::litAt (MEM-R1a), so the pool is bounded by the distinct names (and two-character scope codes) a server ever sees.
//
// FRONT CACHE. Names go through rw::internCached (a per-thread, 512-slot cache before the shard lock). Measured: without it the
// warm (--cache) path, which re-interns every cached row's names from parallel readers, cost envoy +7.6 % user / +2.7 %
// instructions (`sample`: waits on the shard mutexes).

#include "infra/internedtext.h"

// constinit where std::mutex's constructor is constexpr; MSVC's STL made it so only recently (then the pool is still constant-
// initialised in practice, just not enforced at compile time).
#if defined( _MSVC_STL_VERSION )
    #define RW_REF_CONSTINIT
#else
    #define RW_REF_CONSTINIT constinit
#endif

namespace rw
{
inline RW_REF_CONSTINIT NoDestroy<TextPool> gRefTextPoolStorage;

struct RefNames
{
    static TextPool& pool() noexcept { return gRefTextPoolStorage.value; }
};

// A reference name. No std::hash, no id accessor (infra/internedtext.h DETERMINISM).
using InternedText = InternedTextOf<RefNames>;
static_assert( sizeof( InternedText ) == 4, "a reference name is one u32 id: the whole point of the pool" );
}   // namespace rw
