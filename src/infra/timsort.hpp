/*
 * C++ implementation of timsort
 *
 * ported from Python's and OpenJDK's:
 * - http://svn.python.org/projects/python/trunk/Objects/listobject.c
 * - http://cr.openjdk.java.net/~martin/webrevs/openjdk7/timsort/raw_files/new/src/share/classes/java/util/TimSort.java
 *
 * Copyright (c) 2011 Fuji, Goro (gfx) <gfuji@cpan.org>.
 * Copyright (c) 2019-2024 Morwenn.
 * Copyright (c) 2021 Igor Kushnir <igorkuo@gmail.com>.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

// ─────────────────────────────────────────────────────────────────────────────────────────────────────
//  VENDORED — read this before you change, move or upgrade this file.
//
//  SPDX-License-Identifier: MIT
//
//  UPSTREAM PIN
//      github.com/timsort/cpp-TimSort, release tag v3.0.1, vendored verbatim, plus ONE LOCAL PATCH
//      described below. Header-only, no build step, no host-installed dependency (G3).
//
//  THE VERSION MACRO BELOW IS NOT A VERSION. Upstream shipped v3.0.1 WITHOUT bumping
//      GFX_TIMSORT_VERSION_PATCH: it reads 0 at the v3.0.0 tag and 0 at the v3.0.1 tag. So
//      "3 / 0 / 0" identifies neither release, and a reader who trusts it will conclude this file is
//      v3.0.0. It is not. What distinguishes v3.0.1 is content: a single-template-parameter
//      detail::TimSort with per-member Compare/Projection templates, std::iter_difference_t in place of
//      iterator_traits, and binarySort delegating to rotateRight. All three are present below.
//
//  THE LOCAL PATCH — gfx::timsort_workspace, and why it is not upstream
//      Upstream constructs a detail::TimSort per call, and that object OWNS its merge buffer (tmp_) and
//      its run stack (pending_). Every sort therefore reaches the allocator, however hot the caller is.
//      NO upstream release has ever offered a caller-owned alternative: timsort_workspace appears in
//      none of upstream's thirteen tags, nor on its default branch. It is a local addition, carried
//      here deliberately, and it is the ONLY reason to prefer this file over the plain release.
//
//      The patch is mechanical and confined to detail::TimSort's storage and entry points:
//        * a new gfx::timsort_workspace<Iterator> holding the two vectors, with reserve_for( n ) —
//          ceil( n / 2 ) elements, which is timsort's worst-case merge buffer, since it always copies
//          the SHORTER of the two runs it is merging — plus clear() and the two capacity readers;
//        * detail::TimSort keeps its own vectors for the ordinary path and binds tmp_ / pending_ as
//          REFERENCES to either those or the workspace's, so exactly one code path does the sorting;
//        * the static sort()/merge() entry points gain workspace overloads, and gfx::timsort /
//          gfx::timmerge gain the matching public ones.
//      No comparison, merge, galloping or run-detection logic is touched.
//
//      What it buys: after ONE reserve_for, a sort through the workspace overload performs ZERO heap
//      allocations, so a hot caller can sort without touching the allocator (G2, the same property
//      radixSort.h's caller-owned scratch buys). Both vectors are cleared, never shrunk, between uses.
//      The property holds for value types that do not themselves allocate; a vector of std::string
//      allocates in the moves regardless of where the buffer came from.
//
//  ⚠  UPGRADING THIS FILE SILENTLY DELETES THAT PROPERTY.
//      Dropping a newer upstream release over this one compiles, sorts correctly, and passes any test
//      that only checks output — while turning every workspace caller back into one that allocates per
//      call. Re-apply the patch on any bump. test/timsortcheck.sh is the alarm: arm E requires zero
//      allocations across 200 sorts after one reserve_for, arm F requires the owning path to allocate
//      on the same input so arm E cannot pass by being dead, and arm G proves the pair can go red by
//      rebinding the workspace constructor to its own vectors — which is precisely what a naive
//      re-vendor produces.
//
//  STATUS IN THIS TREE: available, and called by nothing. It was measured against std::sort, radix,
//      pdqsort, std::stable_sort and a three-line std::is_sorted guard and won on no shape; fastSort.h's
//      header comment carries the numbers and the decision rule. Do not route a caller here without
//      reading them.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────

#ifndef GFX_TIMSORT_HPP
#define GFX_TIMSORT_HPP

#include <algorithm>
#include <cstddef>
#include <functional>
#include <iterator>
#include <ranges>
#include <utility>
#include <vector>

// Semantic versioning macros

#define GFX_TIMSORT_VERSION_MAJOR 3
#define GFX_TIMSORT_VERSION_MINOR 0
#define GFX_TIMSORT_VERSION_PATCH 0

// Diagnostic selection macros

#if defined(GFX_TIMSORT_ENABLE_ASSERT) || defined(GFX_TIMSORT_ENABLE_AUDIT)
#   include <cassert>
#   define GFX_TIMSORT_ASSERT(expr) assert(expr)
#else
#   define GFX_TIMSORT_ASSERT(expr) ((void)0)
#endif

#ifdef GFX_TIMSORT_ENABLE_AUDIT
#   define GFX_TIMSORT_AUDIT(expr) assert(expr)
#else
#   define GFX_TIMSORT_AUDIT(expr) ((void)0)
#endif

#ifdef GFX_TIMSORT_ENABLE_LOG
#   include <iostream>
#   define GFX_TIMSORT_LOG(expr) (std::clog << "# " << __func__ << ": " << expr << std::endl)
#else
#   define GFX_TIMSORT_LOG(expr) ((void)0)
#endif


namespace gfx {

// ---------------------------------------
// Implementation details
// ---------------------------------------

namespace detail {

template <typename Iterator>
struct run {
    using diff_t = typename std::iterator_traits<Iterator>::difference_type;

    Iterator base;
    diff_t len;

    run(Iterator b, diff_t l) : base(b), len(l) {
    }
};

template <typename RandomAccessIterator>
class TimSort;

} // namespace detail

/**
 * Reusable scratch storage for timsort/timmerge.
 *
 * Reserve it once for the maximum frame size, then pass it to the workspace
 * overloads to avoid per-call allocations in hot loops.
 */
template <std::random_access_iterator Iterator>
class timsort_workspace {
    using run_t = detail::run<Iterator>;

    static constexpr std::size_t PENDING_RUN_CAPACITY = 128;

    std::vector<std::iter_value_t<Iterator>> tmp_;
    std::vector<run_t> pending_;

    template <typename RandomAccessIterator>
    friend class detail::TimSort;

public:
    using value_type = std::iter_value_t<Iterator>;

    void reserve_for(std::size_t elementCount) {
        std::size_t const tmpCount = elementCount / 2 + (elementCount & 1);
        tmp_.reserve(tmpCount);
        pending_.reserve(PENDING_RUN_CAPACITY);
    }

    void clear() noexcept {
        tmp_.clear();
        pending_.clear();
    }

    [[nodiscard]] std::size_t temp_capacity() const noexcept {
        return tmp_.capacity();
    }

    [[nodiscard]] std::size_t pending_capacity() const noexcept {
        return pending_.capacity();
    }
};

namespace detail {

template <typename RandomAccessIterator>
class TimSort {
    using iter_t = RandomAccessIterator;
    using diff_t = std::iter_difference_t<iter_t>;
    using value_t = std::iter_value_t<iter_t>;
    using run_t = run<RandomAccessIterator>;

    static constexpr int MIN_MERGE = 32;
    static constexpr int MIN_GALLOP = 7;

    int minGallop_ = MIN_GALLOP;
    std::vector<value_t> ownedTmp_;
    std::vector<run_t> ownedPending_;
    std::vector<value_t>& tmp_; // temp storage for merges
    std::vector<run_t>& pending_;

    template <typename Compare, typename Projection>
    static void binarySort(iter_t const lo, iter_t const hi, iter_t start,
                           Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(lo <= start);
        GFX_TIMSORT_ASSERT(start <= hi);
        if (start == lo) {
            ++start;
        }
        for (; start < hi; ++start) {
            GFX_TIMSORT_ASSERT(lo <= start);
            auto pos = std::ranges::upper_bound(lo, start, std::invoke(proj, *start), comp, proj);
            rotateRight(pos, std::ranges::next(start));
        }
    }

    template <typename Compare, typename Projection>
    static diff_t countRunAndMakeAscending(iter_t const lo, iter_t const hi,
                                           Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(lo < hi);

        auto runHi = std::ranges::next(lo);
        if (runHi == hi) {
            return 1;
        }

        if (std::invoke(comp, std::invoke(proj, *runHi), std::invoke(proj, *lo))) { // decreasing
            do {
                ++runHi;
            } while (runHi < hi && std::invoke(comp,
                                               std::invoke(proj, *runHi),
                                               std::invoke(proj, *std::ranges::prev(runHi))));
            std::ranges::reverse(lo, runHi);
        } else { // non-decreasing
            do {
                ++runHi;
            } while (runHi < hi && !std::invoke(comp,
                                                std::invoke(proj, *runHi),
                                                std::invoke(proj, *std::ranges::prev(runHi))));
        }

        return runHi - lo;
    }

    static diff_t minRunLength(diff_t n) {
        GFX_TIMSORT_ASSERT(n >= 0);

        diff_t r = 0;
        while (n >= 2 * MIN_MERGE) {
            r |= (n & 1);
            n >>= 1;
        }
        return n + r;
    }

    void pushRun(iter_t const runBase, diff_t const runLen) {
        pending_.emplace_back(runBase, runLen);
    }

    template <typename Compare, typename Projection>
    void mergeCollapse(Compare comp, Projection proj) {
        while (pending_.size() > 1) {
            diff_t n = pending_.size() - 2;

            if ((n > 0 && pending_[n - 1].len <= pending_[n].len + pending_[n + 1].len) ||
                (n > 1 && pending_[n - 2].len <= pending_[n - 1].len + pending_[n].len)) {
                if (pending_[n - 1].len < pending_[n + 1].len) {
                    --n;
                }
                mergeAt(n, comp, proj);
            } else if (pending_[n].len <= pending_[n + 1].len) {
                mergeAt(n, comp, proj);
            } else {
                break;
            }
        }
    }

    template <typename Compare, typename Projection>
    void mergeForceCollapse(Compare comp, Projection proj) {
        while (pending_.size() > 1) {
            diff_t n = pending_.size() - 2;

            if (n > 0 && pending_[n - 1].len < pending_[n + 1].len) {
                --n;
            }
            mergeAt(n, comp, proj);
        }
    }

    template <typename Compare, typename Projection>
    void mergeAt(diff_t const i, Compare comp, Projection proj) {
        diff_t const stackSize = pending_.size();
        GFX_TIMSORT_ASSERT(stackSize >= 2);
        GFX_TIMSORT_ASSERT(i >= 0);
        GFX_TIMSORT_ASSERT(i == stackSize - 2 || i == stackSize - 3);

        auto base1 = pending_[i].base;
        auto len1 = pending_[i].len;
        auto base2 = pending_[i + 1].base;
        auto len2 = pending_[i + 1].len;

        pending_[i].len = len1 + len2;

        if (i == stackSize - 3) {
            pending_[i + 1] = pending_[i + 2];
        }

        pending_.pop_back();

        mergeConsecutiveRuns(base1, len1, base2, len2, std::move(comp), std::move(proj));
    }

    template <typename Compare, typename Projection>
    void mergeConsecutiveRuns(iter_t base1, diff_t len1, iter_t base2, diff_t len2,
                              Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(len1 > 0);
        GFX_TIMSORT_ASSERT(len2 > 0);
        GFX_TIMSORT_ASSERT(base1 + len1 == base2);

        auto k = gallopRight(std::invoke(proj, *base2), base1, len1, 0, comp, proj);
        GFX_TIMSORT_ASSERT(k >= 0);

        base1 += k;
        len1 -= k;

        if (len1 == 0) {
            return;
        }

        len2 = gallopLeft(std::invoke(proj, base1[len1 - 1]), base2, len2, len2 - 1, comp, proj);
        GFX_TIMSORT_ASSERT(len2 >= 0);
        if (len2 == 0) {
            return;
        }

        if (len1 <= len2) {
            mergeLo(base1, len1, base2, len2, comp, proj);
        } else {
            mergeHi(base1, len1, base2, len2, comp, proj);
        }
    }

    template <typename T, typename Iter, typename Compare, typename Projection>
    static diff_t gallopLeft(T const& key, Iter const base, diff_t const len, diff_t const hint,
                             Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(len > 0);
        GFX_TIMSORT_ASSERT(hint >= 0);
        GFX_TIMSORT_ASSERT(hint < len);

        diff_t lastOfs = 0;
        diff_t ofs = 1;

        if (std::invoke(comp, std::invoke(proj, base[hint]), key)) {
            auto maxOfs = len - hint;
            while (ofs < maxOfs && std::invoke(comp, std::invoke(proj, base[hint + ofs]), key)) {
                lastOfs = ofs;
                ofs = (ofs << 1) + 1;

                if (ofs <= 0) { // int overflow
                    ofs = maxOfs;
                }
            }
            if (ofs > maxOfs) {
                ofs = maxOfs;
            }

            lastOfs += hint;
            ofs += hint;
        } else {
            diff_t const maxOfs = hint + 1;
            while (ofs < maxOfs && !std::invoke(comp, std::invoke(proj, base[hint - ofs]), key)) {
                lastOfs = ofs;
                ofs = (ofs << 1) + 1;

                if (ofs <= 0) {
                    ofs = maxOfs;
                }
            }
            if (ofs > maxOfs) {
                ofs = maxOfs;
            }

            diff_t const tmp = lastOfs;
            lastOfs = hint - ofs;
            ofs = hint - tmp;
        }
        GFX_TIMSORT_ASSERT(-1 <= lastOfs);
        GFX_TIMSORT_ASSERT(lastOfs < ofs);
        GFX_TIMSORT_ASSERT(ofs <= len);

        return std::ranges::lower_bound(base + (lastOfs + 1), base + ofs, key, comp, proj) - base;
    }

    template <typename T, typename Iter, typename Compare, typename Projection>
    static diff_t gallopRight(T const& key, Iter const base, diff_t const len, diff_t const hint,
                              Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(len > 0);
        GFX_TIMSORT_ASSERT(hint >= 0);
        GFX_TIMSORT_ASSERT(hint < len);

        diff_t ofs = 1;
        diff_t lastOfs = 0;

        if (std::invoke(comp, key, std::invoke(proj, base[hint]))) {
            diff_t const maxOfs = hint + 1;
            while (ofs < maxOfs && std::invoke(comp, key, std::invoke(proj, base[hint - ofs]))) {
                lastOfs = ofs;
                ofs = (ofs << 1) + 1;

                if (ofs <= 0) {
                    ofs = maxOfs;
                }
            }
            if (ofs > maxOfs) {
                ofs = maxOfs;
            }

            diff_t const tmp = lastOfs;
            lastOfs = hint - ofs;
            ofs = hint - tmp;
        } else {
            diff_t const maxOfs = len - hint;
            while (ofs < maxOfs && !std::invoke(comp, key, std::invoke(proj, base[hint + ofs]))) {
                lastOfs = ofs;
                ofs = (ofs << 1) + 1;

                if (ofs <= 0) { // int overflow
                    ofs = maxOfs;
                }
            }
            if (ofs > maxOfs) {
                ofs = maxOfs;
            }

            lastOfs += hint;
            ofs += hint;
        }
        GFX_TIMSORT_ASSERT(-1 <= lastOfs);
        GFX_TIMSORT_ASSERT(lastOfs < ofs);
        GFX_TIMSORT_ASSERT(ofs <= len);

        return std::ranges::upper_bound(base + (lastOfs + 1), base + ofs, key, comp, proj) - base;
    }

    static void rotateLeft(iter_t first, iter_t last) {
        std::iter_value_t<iter_t> tmp = std::ranges::iter_move(first);
        auto [_, last_1] = std::ranges::move(std::ranges::next(first), last, first);
        *last_1 = std::move(tmp);
    }

    static void rotateRight(iter_t first, iter_t last) {
        auto last_1 = std::ranges::prev(last);
        std::iter_value_t<iter_t> tmp = std::ranges::iter_move(last_1);
        std::ranges::move_backward(first, last_1, last);
        *first = std::move(tmp);
    }

    template <typename Compare, typename Projection>
    void mergeLo(iter_t const base1, diff_t len1, iter_t const base2, diff_t len2,
                 Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(len1 > 0);
        GFX_TIMSORT_ASSERT(len2 > 0);
        GFX_TIMSORT_ASSERT(base1 + len1 == base2);

        if (len1 == 1) {
            return rotateLeft(base1, base2 + len2);
        }
        if (len2 == 1) {
            return rotateRight(base1, base2 + len2);
        }

        move_to_tmp(base1, len1);

        auto cursor1 = tmp_.begin();
        auto cursor2 = base2;
        auto dest = base1;

        *dest = std::ranges::iter_move(cursor2);
        ++cursor2;
        ++dest;
        --len2;

        int minGallop(minGallop_);

        // outer:
        while (true) {
            diff_t count1 = 0;
            diff_t count2 = 0;

            do {
                GFX_TIMSORT_ASSERT(len1 > 1);
                GFX_TIMSORT_ASSERT(len2 > 0);

                if (std::invoke(comp, std::invoke(proj, *cursor2), std::invoke(proj, *cursor1))) {
                    *dest = std::ranges::iter_move(cursor2);
                    ++cursor2;
                    ++dest;
                    ++count2;
                    count1 = 0;
                    if (--len2 == 0) {
                        goto epilogue;
                    }
                } else {
                    *dest = std::ranges::iter_move(cursor1);
                    ++cursor1;
                    ++dest;
                    ++count1;
                    count2 = 0;
                    if (--len1 == 1) {
                        goto epilogue;
                    }
                }
            } while ((count1 | count2) < minGallop);

            do {
                GFX_TIMSORT_ASSERT(len1 > 1);
                GFX_TIMSORT_ASSERT(len2 > 0);

                count1 = gallopRight(std::invoke(proj, *cursor2), cursor1, len1, 0, comp, proj);
                if (count1 != 0) {
                    std::ranges::move_backward(cursor1, cursor1 + count1, dest + count1);
                    dest += count1;
                    cursor1 += count1;
                    len1 -= count1;

                    if (len1 <= 1) {
                        goto epilogue;
                    }
                }
                *dest = std::ranges::iter_move(cursor2);
                ++cursor2;
                ++dest;
                if (--len2 == 0) {
                    goto epilogue;
                }

                count2 = gallopLeft(std::invoke(proj, *cursor1), cursor2, len2, 0, comp, proj);
                if (count2 != 0) {
                    std::ranges::move(cursor2, cursor2 + count2, dest);
                    dest += count2;
                    cursor2 += count2;
                    len2 -= count2;
                    if (len2 == 0) {
                        goto epilogue;
                    }
                }
                *dest = std::ranges::iter_move(cursor1);
                ++cursor1;
                ++dest;
                if (--len1 == 1) {
                    goto epilogue;
                }

                --minGallop;
            } while ((count1 >= MIN_GALLOP) | (count2 >= MIN_GALLOP));

            if (minGallop < 0) {
                minGallop = 0;
            }
            minGallop += 2;
        } // end of "outer" loop

        epilogue: // merge what is left from either cursor1 or cursor2

        minGallop_ = (std::min)(minGallop, 1);

        if (len1 == 1) {
            GFX_TIMSORT_ASSERT(len2 > 0);
            std::ranges::move(cursor2, cursor2 + len2, dest);
            *(dest + len2) = std::ranges::iter_move(cursor1);
        } else {
            GFX_TIMSORT_ASSERT(len1 != 0 && "Comparison function violates its general contract");
            GFX_TIMSORT_ASSERT(len2 == 0);
            GFX_TIMSORT_ASSERT(len1 > 1);
            std::ranges::move(cursor1, cursor1 + len1, dest);
        }
    }

    template <typename Compare, typename Projection>
    void mergeHi(iter_t const base1, diff_t len1, iter_t const base2, diff_t len2,
                 Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(len1 > 0);
        GFX_TIMSORT_ASSERT(len2 > 0);
        GFX_TIMSORT_ASSERT(base1 + len1 == base2);

        if (len1 == 1) {
            return rotateLeft(base1, base2 + len2);
        }
        if (len2 == 1) {
            return rotateRight(base1, base2 + len2);
        }

        move_to_tmp(base2, len2);

        auto cursor1 = base1 + len1;
        auto cursor2 = tmp_.begin() + (len2 - 1);
        auto dest = base2 + (len2 - 1);

        *dest = std::ranges::iter_move(--cursor1);
        --dest;
        --len1;

        int minGallop(minGallop_);

        // outer:
        while (true) {
            diff_t count1 = 0;
            diff_t count2 = 0;

            // The next loop is a hot path of the algorithm, so we decrement
            // eagerly the cursor so that it always points directly to the value
            // to compare, but we have to implement some trickier logic to make
            // sure that it points to the next value again by the end of said loop
            --cursor1;

            do {
                GFX_TIMSORT_ASSERT(len1 > 0);
                GFX_TIMSORT_ASSERT(len2 > 1);

                if (std::invoke(comp, std::invoke(proj, *cursor2), std::invoke(proj, *cursor1))) {
                    *dest = std::ranges::iter_move(cursor1);
                    --dest;
                    ++count1;
                    count2 = 0;
                    if (--len1 == 0) {
                        goto epilogue;
                    }
                    --cursor1;
                } else {
                    *dest = std::ranges::iter_move(cursor2);
                    --cursor2;
                    --dest;
                    ++count2;
                    count1 = 0;
                    if (--len2 == 1) {
                        ++cursor1; // See comment before the loop
                        goto epilogue;
                    }
                }
            } while ((count1 | count2) < minGallop);
            ++cursor1; // See comment before the loop

            do {
                GFX_TIMSORT_ASSERT(len1 > 0);
                GFX_TIMSORT_ASSERT(len2 > 1);

                count1 = len1 - gallopRight(std::invoke(proj, *cursor2),
                                            base1, len1, len1 - 1, comp, proj);
                if (count1 != 0) {
                    dest -= count1;
                    cursor1 -= count1;
                    len1 -= count1;
                    std::ranges::move_backward(cursor1, cursor1 + count1, dest + (1 + count1));

                    if (len1 == 0) {
                        goto epilogue;
                    }
                }
                *dest = std::ranges::iter_move(cursor2);
                --cursor2;
                --dest;
                if (--len2 == 1) {
                    goto epilogue;
                }

                count2 = len2 - gallopLeft(std::invoke(proj, *std::ranges::prev(cursor1)),
                                           tmp_.begin(), len2, len2 - 1, comp, proj);
                if (count2 != 0) {
                    dest -= count2;
                    cursor2 -= count2;
                    len2 -= count2;
                    std::ranges::move(std::ranges::next(cursor2),
                                      cursor2 + (1 + count2),
                                      std::ranges::next(dest));
                    if (len2 <= 1) {
                        goto epilogue;
                    }
                }
                *dest = std::ranges::iter_move(--cursor1);
                --dest;
                if (--len1 == 0) {
                    goto epilogue;
                }

                --minGallop;
            } while ((count1 >= MIN_GALLOP) | (count2 >= MIN_GALLOP));

            if (minGallop < 0) {
                minGallop = 0;
            }
            minGallop += 2;
        } // end of "outer" loop

        epilogue: // merge what is left from either cursor1 or cursor2

        minGallop_ = (std::min)(minGallop, 1);

        if (len2 == 1) {
            GFX_TIMSORT_ASSERT(len1 > 0);
            dest -= len1;
            std::ranges::move_backward(cursor1 - len1, cursor1, dest + (1 + len1));
            *dest = std::ranges::iter_move(cursor2);
        } else {
            GFX_TIMSORT_ASSERT(len2 != 0 && "Comparison function violates its general contract");
            GFX_TIMSORT_ASSERT(len1 == 0);
            GFX_TIMSORT_ASSERT(len2 > 1);
            std::ranges::move(tmp_.begin(), tmp_.begin() + len2, dest - (len2 - 1));
        }
    }

    void move_to_tmp(iter_t const begin, diff_t len) {
        tmp_.assign(std::make_move_iterator(begin),
                    std::make_move_iterator(begin + len));
    }

    template <typename Compare, typename Projection>
    void mergeImpl(iter_t const lo, iter_t const mid, iter_t const hi,
                   Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(lo <= mid);
        GFX_TIMSORT_ASSERT(mid <= hi);

        if (lo == mid || mid == hi) {
            return; // nothing to do
        }

        mergeConsecutiveRuns(lo, mid - lo, mid, hi - mid, std::move(comp), std::move(proj));

        GFX_TIMSORT_LOG("1st size: " << (mid - lo) << "; 2nd size: " << (hi - mid)
                                     << "; tmp_.size(): " << tmp_.size());
    }

    template <typename Compare, typename Projection>
    void sortImpl(iter_t const lo, iter_t const hi, Compare comp, Projection proj) {
        GFX_TIMSORT_ASSERT(lo <= hi);

        auto nRemaining = hi - lo;
        if (nRemaining < 2) {
            return; // nothing to do
        }

        if (nRemaining < MIN_MERGE) {
            auto initRunLen = countRunAndMakeAscending(lo, hi, comp, proj);
            GFX_TIMSORT_LOG("initRunLen: " << initRunLen);
            binarySort(lo, hi, lo + initRunLen, comp, proj);
            return;
        }

        auto minRun = minRunLength(nRemaining);
        auto cur = lo;
        do {
            auto runLen = countRunAndMakeAscending(cur, hi, comp, proj);

            if (runLen < minRun) {
                auto force = (std::min)(nRemaining, minRun);
                binarySort(cur, cur + force, cur + runLen, comp, proj);
                runLen = force;
            }

            pushRun(cur, runLen);
            mergeCollapse(comp, proj);

            cur += runLen;
            nRemaining -= runLen;
        } while (nRemaining != 0);

        GFX_TIMSORT_ASSERT(cur == hi);
        mergeForceCollapse(comp, proj);
        GFX_TIMSORT_ASSERT(pending_.size() == 1);

        GFX_TIMSORT_LOG("size: " << (hi - lo) << " tmp_.size(): " << tmp_.size()
                                 << " pending_.size(): " << pending_.size());
    }

public:
    TimSort() : tmp_(ownedTmp_), pending_(ownedPending_) {
    }

    explicit TimSort(timsort_workspace<iter_t>& workspace)
        : tmp_(workspace.tmp_), pending_(workspace.pending_) {
        tmp_.clear();
        pending_.clear();
    }

    ~TimSort() {
        tmp_.clear();
        pending_.clear();
    }

    template <typename Compare, typename Projection>
    static void merge(iter_t const lo, iter_t const mid, iter_t const hi,
                      Compare comp, Projection proj) {
        TimSort ts;
        ts.mergeImpl(lo, mid, hi, std::move(comp), std::move(proj));
    }

    template <typename Compare, typename Projection>
    static void merge(iter_t const lo, iter_t const mid, iter_t const hi,
                      Compare comp, Projection proj, timsort_workspace<iter_t>& workspace) {
        TimSort ts(workspace);
        ts.mergeImpl(lo, mid, hi, std::move(comp), std::move(proj));
    }

    template <typename Compare, typename Projection>
    static void sort(iter_t const lo, iter_t const hi, Compare comp, Projection proj) {
        TimSort ts;
        ts.sortImpl(lo, hi, std::move(comp), std::move(proj));
    }

    template <typename Compare, typename Projection>
    static void sort(iter_t const lo, iter_t const hi, Compare comp, Projection proj,
                     timsort_workspace<iter_t>& workspace) {
        TimSort ts(workspace);
        ts.sortImpl(lo, hi, std::move(comp), std::move(proj));
    }
};

} // namespace detail


// ---------------------------------------
// Public interface implementation
// ---------------------------------------

/**
 * Stably merges two consecutive sorted ranges [first, middle) and [middle, last) into one
 * sorted range [first, last) with a comparison function and a projection function.
 */
template <
    std::random_access_iterator Iterator,
    std::sentinel_for<Iterator> Sentinel,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<Iterator, Compare, Projection>
auto timmerge(Iterator first, Iterator middle, Sentinel last,
              Compare comp={}, Projection proj={})
    -> Iterator
{
    auto last_it = std::ranges::next(first, last);
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(first, middle, comp, proj) && "Precondition");
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(middle, last_it, comp, proj) && "Precondition");
    detail::TimSort<Iterator>::merge(first, middle, last_it, comp, proj);
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(first, last_it, comp, proj) && "Postcondition");
    return last_it;
}

/**
 * Stably merges two consecutive sorted ranges [first, middle) and [middle, last) into one
 * sorted range [first, last) with caller-owned reusable scratch storage.
 */
template <
    std::random_access_iterator Iterator,
    std::sentinel_for<Iterator> Sentinel,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<Iterator, Compare, Projection>
auto timmerge(Iterator first, Iterator middle, Sentinel last,
              timsort_workspace<Iterator>& workspace,
              Compare comp={}, Projection proj={})
    -> Iterator
{
    auto last_it = std::ranges::next(first, last);
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(first, middle, comp, proj) && "Precondition");
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(middle, last_it, comp, proj) && "Precondition");
    detail::TimSort<Iterator>::merge(first, middle, last_it, comp, proj, workspace);
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(first, last_it, comp, proj) && "Postcondition");
    return last_it;
}

/**
 * Stably merges two sorted halves [first, middle) and [middle, last) of a range into one
 * sorted range [first, last) with a comparison function and a projection function.
 */
template <
    std::ranges::random_access_range Range,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<std::ranges::iterator_t<Range>, Compare, Projection>
auto timmerge(Range &&range, std::ranges::iterator_t<Range> middle,
              Compare comp={}, Projection proj={})
    -> std::ranges::borrowed_iterator_t<Range>
{
    return gfx::timmerge(std::begin(range), middle, std::end(range), comp, proj);
}

/**
 * Stably merges two sorted halves [first, middle) and [middle, last) of a range into one
 * sorted range [first, last) with caller-owned reusable scratch storage.
 */
template <
    std::ranges::random_access_range Range,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<std::ranges::iterator_t<Range>, Compare, Projection>
auto timmerge(Range &&range, std::ranges::iterator_t<Range> middle,
              timsort_workspace<std::ranges::iterator_t<Range>>& workspace,
              Compare comp={}, Projection proj={})
    -> std::ranges::borrowed_iterator_t<Range>
{
    return gfx::timmerge(std::begin(range), middle, std::end(range), workspace, comp, proj);
}

/**
 * Stably sorts a range with a comparison function and a projection function.
 */
template <
    std::random_access_iterator Iterator,
    std::sentinel_for<Iterator> Sentinel,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<Iterator, Compare, Projection>
auto timsort(Iterator first, Sentinel last,
             Compare comp={}, Projection proj={})
    -> Iterator
{
    auto last_it = std::ranges::next(first, last);
    detail::TimSort<Iterator>::sort(first, last_it, comp, proj);
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(first, last_it, comp, proj) && "Postcondition");
    return last_it;
}

/**
 * Stably sorts a range with caller-owned reusable scratch storage.
 */
template <
    std::random_access_iterator Iterator,
    std::sentinel_for<Iterator> Sentinel,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<Iterator, Compare, Projection>
auto timsort(Iterator first, Sentinel last,
             timsort_workspace<Iterator>& workspace,
             Compare comp={}, Projection proj={})
    -> Iterator
{
    auto last_it = std::ranges::next(first, last);
    detail::TimSort<Iterator>::sort(first, last_it, comp, proj, workspace);
    GFX_TIMSORT_AUDIT(std::ranges::is_sorted(first, last_it, comp, proj) && "Postcondition");
    return last_it;
}

/**
 * Stably sorts a range with a comparison function and a projection function.
 */
template <
    std::ranges::random_access_range Range,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<std::ranges::iterator_t<Range>, Compare, Projection>
auto timsort(Range &&range, Compare comp={}, Projection proj={})
    -> std::ranges::borrowed_iterator_t<Range>
{
    return gfx::timsort(std::begin(range), std::end(range), comp, proj);
}

/**
 * Stably sorts a range with caller-owned reusable scratch storage.
 */
template <
    std::ranges::random_access_range Range,
    typename Compare = std::ranges::less,
    typename Projection = std::identity
>
    requires std::sortable<std::ranges::iterator_t<Range>, Compare, Projection>
auto timsort(Range &&range,
             timsort_workspace<std::ranges::iterator_t<Range>>& workspace,
             Compare comp={}, Projection proj={})
    -> std::ranges::borrowed_iterator_t<Range>
{
    return gfx::timsort(std::begin(range), std::end(range), workspace, comp, proj);
}

} // namespace gfx

#undef GFX_TIMSORT_ENABLE_ASSERT
#undef GFX_TIMSORT_ASSERT
#undef GFX_TIMSORT_ENABLE_AUDIT
#undef GFX_TIMSORT_AUDIT
#undef GFX_TIMSORT_ENABLE_LOG
#undef GFX_TIMSORT_LOG

#endif // GFX_TIMSORT_HPP
