#pragma once

// namesplit.h — the ONE balanced-trailing-group scanner for qualified/templated NAME strings.
//
// WHY THIS EXISTS (H4, PLAN_h4QualifiedCalls_2026-07-30.md §Execution / W1 verdict). Two unrelated surfaces
// need to strip a trailing balanced `<…>` (or `(…)`) group off a name spelling:
//   * tracelocus.h — a demangled stack frame (`make<Foo,Bar>(int) const` → `make`) before the symbol lookup.
//   * ingest.cpp   — the C++ qualified-call re-split, where the scope half of `numeric_limits<std::size_t>::max`
//                    must lose its template arguments before `immediateScope()` takes its last `::` segment
//                    (otherwise the qualifier extracts as the garbage `size_t>` and the canonical tier misses).
// ingest.cpp cannot include tracelocus.h (that header pulls graph.h + serialize.h — the whole model), so the
// scanner lives here, in a leaf header with no ripwire dependency but Diagnostics.h. Duplicating it was the
// alternative and is exactly the clone class `--quality-delta` flags.
//
// tracelocus.h keeps its `tracelocus_detail::stripTrailingGroup` / `stripTemplateArgs` spellings via
// using-declarations, so every existing call site and its gates stay BYTE-IDENTICAL — this hoist moved code,
// it did not change behaviour.

#include "Diagnostics.h"   // VERIFY — the depth invariant below

#include <cstddef>
#include <string_view>

namespace rw
{
namespace namesplit
{

// the head of `f` before its trailing BALANCED `open…close` group, or `f` unchanged when there is no such
// group or stripping it would eat the name itself. ONE scan for both delimiter pairs (call signatures and
// template arguments), so the two strippers below can never drift apart. Guards, in order: nothing to strip
// (`<module>`, `(int)` alone); an `->` tail; and an `operator` name whose delimiters ARE the name
// (`operator()`, `operator<`, `operator<<`).
// THE LOOP SHAPE IS LOAD-BEARING, not style. This was written as `for( std::size_t i = f.size(); i-- > 0; )`
// — the classic reverse-scan idiom — whose FINAL test decrements 0 and wraps `i` to SIZE_MAX. That wrap is a
// well-defined unsigned overflow in C++, but `-fsanitize=integer` reports it, and the G1 stack runs with
// `-fno-sanitize-recover=all`, so the process ABORTS. It only fires when the scan runs off the front, i.e.
// on an UNBALANCED trailing group — which a C++ operator name supplies routinely: a demangled frame
// `nsx::ops::operator>(S const&, S const&)` reduces to `nsx::ops::operator>`, whose trailing `>` has no
// opener. Measured before the fix: `asan/ripwire <corpus> --from-trace=<that frame>` exited 134.
// The `cursor`/`index` split below cannot wrap: cursor is only decremented while it is strictly positive.
inline std::string_view stripTrailingGroup( std::string_view f, char open, char close ) noexcept
{
    if( f.empty() || f.back() != close ) return f;

    std::size_t depth = 0;
    for( std::size_t cursor = f.size(); cursor > 0; )
    {
        const std::size_t i = --cursor;
        if( f[i] == close ) ++depth;
        else if( f[i] == open )
        {
            VERIFY( depth > 0 );                                      // depth is seeded by f.back() == close
            if( --depth != 0 ) continue;
            const std::string_view head = f.substr( 0, i );
            if( head.empty() || head.back() == '-' ) return f;
            return head.size() >= 8 && head.substr( head.size() - 8 ) == "operator" ? f : head;
        }
    }
    return f;
}

// drop a trailing balanced `<…>` template-argument group: `make<Foo,Bar>` -> `make`.
inline std::string_view stripTemplateArgs( std::string_view f ) noexcept { return stripTrailingGroup( f, '<', '>' ); }

}   // namespace namesplit
}   // namespace rw
