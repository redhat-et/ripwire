// test/stdqualfix — file 5: a def that IS inside namespace std, through an INLINE namespace — the shape of a
// pre-C++17 polyfill header, and of a vendored standard library. Its immediate scope is "__1", not "std",
// so the canonical tier misses `std::launder` and the site reaches the bare-name spray with TWO candidates:
// this one and arena.h's decoy. The guard must keep THIS one (a def inside std) and drop the decoy.
//
//   pre-fix:  launderIt -> both launder defs, amb="1", two prov="split" edges (one of them wrong)
//   fixed:    launderIt -> std::__1::launder only, no amb=

#pragma once

namespace std
{
inline namespace __1
{
template<class T> T* launder( T* p ) noexcept { return p; }
}
}
