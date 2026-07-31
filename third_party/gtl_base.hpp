#ifndef gtl_base_hpp_guard_
#define gtl_base_hpp_guard_

// ---------------------------------------------------------------------------
// Copyright (c) 2019-2022, Gregory Popovitch - greg7mdp@gmail.com
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Includes work from abseil-cpp (https://github.com/abseil/abseil-cpp)
// with modifications.
//
// Copyright 2018 The Abseil Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ---------------------------------------------------------------------------

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdlib>
#include <functional>
#include <initializer_list>
#include <iterator>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>

#include "gtl_config.hpp"

#ifdef _MSC_VER
    #pragma warning(push)
    #pragma warning(disable : 4514) // unreferenced inline function has been removed
    #pragma warning(disable : 4582) // constructor is not implicitly called
    #pragma warning(disable : 4625) // copy constructor was implicitly defined as deleted
    #pragma warning(disable : 4626) // assignment operator was implicitly defined as deleted
    #pragma warning(disable : 4710) // function not inlined
    #pragma warning(disable : 4711) //  selected for automatic inline expansion
    #pragma warning(disable : 4820) // '6' bytes padding added after data member
#endif                              // _MSC_VER

namespace gtl {
namespace priv {

// ----------------------------------------------------------------------------
// If Pair is a standard-layout type, OffsetOf<Pair>::kFirst and
// OffsetOf<Pair>::kSecond are equivalent to offsetof(Pair, first) and
// offsetof(Pair, second) respectively. Otherwise they are -1.
//
// The purpose of OffsetOf is to avoid calling offsetof() on non-standard-layout
// type, which is non-portable.
// ----------------------------------------------------------------------------
template<class Pair, class = std::true_type>
struct OffsetOf {
    static constexpr size_t kFirst  = static_cast<size_t>(-1);
    static constexpr size_t kSecond = static_cast<size_t>(-1);
};

template<class Pair>
struct OffsetOf<Pair, typename std::is_standard_layout<Pair>::type> {
    static constexpr size_t kFirst  = offsetof(Pair, first);
    static constexpr size_t kSecond = offsetof(Pair, second);
};

// ----------------------------------------------------------------------------
template<class K, class V>
struct IsLayoutCompatible {
private:
    struct Pair {
        K first;
        V second;
    };

    // Is P layout-compatible with Pair?
    template<class P>
    static constexpr bool LayoutCompatible() {
        return std::is_standard_layout<P>() && sizeof(P) == sizeof(Pair) && alignof(P) == alignof(Pair) &&
               OffsetOf<P>::kFirst == OffsetOf<Pair>::kFirst && OffsetOf<P>::kSecond == OffsetOf<Pair>::kSecond;
    }

public:
    // Whether pair<const K, V> and pair<K, V> are layout-compatible. If they are,
    // then it is safe to store them in a union and read from either.
    static constexpr bool value = std::is_standard_layout<K>() && std::is_standard_layout<Pair>() &&
                                  OffsetOf<Pair>::kFirst == 0 && LayoutCompatible<std::pair<K, V>>() &&
                                  LayoutCompatible<std::pair<const K, V>>();
};

// ----------------------------------------------------------------------------
// The internal storage type for key-value containers like flat_hash_map.
//
// It is convenient for the value_type of a flat_hash_map<K, V> to be
// pair<const K, V>; the "const K" prevents accidental modification of the key
// when dealing with the reference returned from find() and similar methods.
// However, this creates other problems; we want to be able to emplace(K, V)
// efficiently with move operations, and similarly be able to move a
// pair<K, V> in insert().
//
// The solution is this union, which aliases the const and non-const versions
// of the pair. This also allows flat_hash_map<const K, V> to work, even though
// that has the same efficiency issues with move in emplace() and insert() -
// but people do it anyway.
//
// If kMutableKeys is false, only the value member can be accessed.
//
// If kMutableKeys is true, key can be accessed through all slots while value
// and mutable_value must be accessed only via INITIALIZED slots. Slots are
// created and destroyed via mutable_value so that the key can be moved later.
//
// Accessing one of the union fields while the other is active is safe as
// long as they are layout-compatible, which is guaranteed by the definition of
// kMutableKeys. For C++11, the relevant section of the standard is
// https://timsong-cpp.github.io/cppwp/n3337/class.mem#19 (9.2.19)
// ----------------------------------------------------------------------------
template<class K, class V>
union map_slot_type {
    map_slot_type() {}
    ~map_slot_type()                               = delete;
    map_slot_type(const map_slot_type&)            = delete;
    map_slot_type& operator=(const map_slot_type&) = delete;

    using value_type         = std::pair<const K, V>;
    using mutable_value_type = std::pair<K, V>;

    value_type         value;
    mutable_value_type mutable_value;
    K                  key;
};

// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
template<class K, class V>
struct map_slot_policy {
    using slot_type          = map_slot_type<K, V>;
    using value_type         = std::pair<const K, V>;
    using mutable_value_type = std::pair<K, V>;

private:
    static void emplace(slot_type* slot) {
        // The construction of union doesn't do anything at runtime but it allows us
        // to access its members without violating aliasing rules.
        new (slot) slot_type;
    }
    // If pair<const K, V> and pair<K, V> are layout-compatible, we can accept one
    // or the other via slot_type. We are also free to access the key via
    // slot_type::key in this case.
    using kMutableKeys = IsLayoutCompatible<K, V>;

public:
    static value_type&       element(slot_type* slot) { return slot->value; }
    static const value_type& element(const slot_type* slot) { return slot->value; }

    static const K& key(const slot_type* slot) { return kMutableKeys::value ? slot->key : slot->value.first; }

    template<class Allocator, class... Args>
    static void construct(Allocator* alloc, slot_type* slot, Args&&... args) {
        emplace(slot);
        if (kMutableKeys::value) {
            std::allocator_traits<Allocator>::construct(*alloc, &slot->mutable_value, std::forward<Args>(args)...);
        } else {
            std::allocator_traits<Allocator>::construct(*alloc, &slot->value, std::forward<Args>(args)...);
        }
    }

    // Construct this slot by moving from another slot.
    template<class Allocator>
    static void construct(Allocator* alloc, slot_type* slot, slot_type* other) {
        emplace(slot);
        if (kMutableKeys::value) {
            std::allocator_traits<Allocator>::construct(*alloc, &slot->mutable_value, std::move(other->mutable_value));
        } else {
            std::allocator_traits<Allocator>::construct(*alloc, &slot->value, std::move(other->value));
        }
    }

    template<class Allocator>
    static void destroy(Allocator* alloc, slot_type* slot) {
        if (kMutableKeys::value) {
            std::allocator_traits<Allocator>::destroy(*alloc, &slot->mutable_value);
        } else {
            std::allocator_traits<Allocator>::destroy(*alloc, &slot->value);
        }
    }

    template<class Allocator>
    static void transfer(Allocator* alloc, slot_type* new_slot, slot_type* old_slot) {
        emplace(new_slot);
        if (kMutableKeys::value) {
            std::allocator_traits<Allocator>::construct(
                *alloc, &new_slot->mutable_value, std::move(old_slot->mutable_value));
        } else {
            std::allocator_traits<Allocator>::construct(*alloc, &new_slot->value, std::move(old_slot->value));
        }
        destroy(alloc, old_slot);
    }

    template<class Allocator>
    static void swap(Allocator* alloc, slot_type* a, slot_type* b) {
        if (kMutableKeys::value) {
            using std::swap;
            swap(a->mutable_value, b->mutable_value);
        } else {
            value_type tmp = std::move(a->value);
            std::allocator_traits<Allocator>::destroy(*alloc, &a->value);
            std::allocator_traits<Allocator>::construct(*alloc, &a->value, std::move(b->value));
            std::allocator_traits<Allocator>::destroy(*alloc, &b->value);
            std::allocator_traits<Allocator>::construct(*alloc, &b->value, std::move(tmp));
        }
    }

    template<class Allocator>
    static void move(Allocator* alloc, slot_type* src, slot_type* dest) {
        if (kMutableKeys::value) {
            dest->mutable_value = std::move(src->mutable_value);
        } else {
            std::allocator_traits<Allocator>::destroy(*alloc, &dest->value);
            std::allocator_traits<Allocator>::construct(*alloc, &dest->value, std::move(src->value));
        }
    }

    template<class Allocator>
    static void move(Allocator* alloc, slot_type* first, slot_type* last, slot_type* result) {
        for (slot_type *src = first, *dest = result; src != last; ++src, ++dest)
            move(alloc, src, dest);
    }
};

// ----------------------------------------------------------------------------
// A type wrapper that instructs `Layout` to use the specific alignment for the
// array. `Layout<..., Aligned<T, N>, ...>` has exactly the same API
// and behavior as `Layout<..., T, ...>` except that the first element of the
// array of `T` is aligned to `N` (the rest of the elements follow without
// padding).
//
// Requires: `N >= alignof(T)` and `N` is a power of 2.
// ----------------------------------------------------------------------------
template<class T, size_t N>
struct Aligned;

namespace internal_layout {

template<class T>
struct NotAligned {};

template<class T, size_t N>
struct NotAligned<const Aligned<T, N>> {
    static_assert(sizeof(T) == 0, "Aligned<T, N> cannot be const-qualified");
};

template<size_t>
using IntToSize = size_t;

template<class>
using TypeToSize = size_t;

template<class T>
struct Type : NotAligned<T> {
    using type = T;
};

template<class T, size_t N>
struct Type<Aligned<T, N>> {
    using type = T;
};

template<class T>
struct SizeOf
    : NotAligned<T>
    , std::integral_constant<size_t, sizeof(T)> {};

template<class T, size_t N>
struct SizeOf<Aligned<T, N>> : std::integral_constant<size_t, sizeof(T)> {};

// Note: workaround for https://gcc.gnu.org/PR88115
template<class T>
struct AlignOf : NotAligned<T> {
    static constexpr size_t value = alignof(T);
};

template<class T, size_t N>
struct AlignOf<Aligned<T, N>> {
    static_assert(N % alignof(T) == 0, "Custom alignment can't be lower than the type's alignment");
    static constexpr size_t value = N;
};

// Does `Ts...` contain `T`?
template<class T, class... Ts>
using Contains = std::disjunction<std::is_same<T, Ts>...>;

template<class From, class To>
using CopyConst = typename std::conditional_t<std::is_const_v<From>, const To, To>;

// This namespace contains no types. It prevents functions defined in it from
// being found by ADL.
// ----------------------------------------------------------------------------
namespace adl_barrier {

template<class Needle, class... Ts>
constexpr size_t Find(Needle, Needle, Ts...) {
    static_assert(!Contains<Needle, Ts...>(), "Duplicate element type");
    return 0;
}

template<class Needle, class T, class... Ts>
constexpr size_t Find(Needle, T, Ts...) {
    return adl_barrier::Find(Needle(), Ts()...) + 1;
}

constexpr bool IsPow2(size_t n) { return !(n & (n - 1)); }

// Returns `q * m` for the smallest `q` such that `q * m >= n`.
// Requires: `m` is a power of two. It's enforced by IsLegalElementType below.
constexpr size_t Align(size_t n, size_t m) { return (n + m - 1) & ~(m - 1); }

constexpr size_t Min(size_t a, size_t b) { return b < a ? b : a; }

constexpr size_t Max(size_t a) { return a; }

template<class... Ts>
constexpr size_t Max(size_t a, size_t b, Ts... rest) {
    return adl_barrier::Max(b < a ? a : b, rest...);
}

} // namespace adl_barrier

template<bool C>
using EnableIf = typename std::enable_if_t<C, int>;

// Can `T` be a template argument of `Layout`?
// ---------------------------------------------------------------------------
template<class T>
using IsLegalElementType =
    std::integral_constant<bool,
                           !std::is_reference_v<T> && !std::is_volatile_v<T> &&
                               !std::is_reference_v<typename Type<T>::type> &&
                               !std::is_volatile_v<typename Type<T>::type> && adl_barrier::IsPow2(AlignOf<T>::value)>;

template<class Elements, class SizeSeq, class OffsetSeq>
class LayoutImpl;

// ---------------------------------------------------------------------------
// Public base class of `Layout` and the result type of `Layout::Partial()`.
//
// `Elements...` contains all template arguments of `Layout` that created this
// instance.
//
// `SizeSeq...` is `[0, NumSizes)` where `NumSizes` is the number of arguments
// passed to `Layout::Partial()` or `Layout::Layout()`.
//
// `OffsetSeq...` is `[0, NumOffsets)` where `NumOffsets` is
// `Min(sizeof...(Elements), NumSizes + 1)` (the number of arrays for which we
// can compute offsets).
// ---------------------------------------------------------------------------
template<class... Elements, size_t... SizeSeq, size_t... OffsetSeq>
class LayoutImpl<std::tuple<Elements...>, std::index_sequence<SizeSeq...>, std::index_sequence<OffsetSeq...>> {
private:
    static_assert(sizeof...(Elements) > 0, "At least one field is required");
    static_assert(std::conjunction_v<IsLegalElementType<Elements>...>, "Invalid element type (see IsLegalElementType)");

    enum {
        NumTypes   = sizeof...(Elements),
        NumSizes   = sizeof...(SizeSeq),
        NumOffsets = sizeof...(OffsetSeq),
    };

    // These are guaranteed by `Layout`.
    static_assert(NumOffsets == adl_barrier::Min(NumTypes, NumSizes + 1), "Internal error");
    static_assert(NumTypes > 0, "Internal error");

    // Returns the index of `T` in `Elements...`. Results in a compilation error
    // if `Elements...` doesn't contain exactly one instance of `T`.
    template<class T>
    static constexpr size_t ElementIndex() {
        static_assert(Contains<Type<T>, Type<typename Type<Elements>::type>...>(), "Type not found");
        return adl_barrier::Find(Type<T>(), Type<typename Type<Elements>::type>()...);
    }

    template<size_t N>
    using ElementAlignment = AlignOf<typename std::tuple_element<N, std::tuple<Elements...>>::type>;

public:
    // Element types of all arrays packed in a tuple.
    using ElementTypes = std::tuple<typename Type<Elements>::type...>;

    // Element type of the Nth array.
    template<size_t N>
    using ElementType = typename std::tuple_element<N, ElementTypes>::type;

    constexpr explicit LayoutImpl(IntToSize<SizeSeq>... sizes)
        : size_{ sizes... } {}

    // Alignment of the layout, equal to the strictest alignment of all elements.
    // All pointers passed to the methods of layout must be aligned to this value.
    static constexpr size_t Alignment() { return adl_barrier::Max(AlignOf<Elements>::value...); }

    // Offset in bytes of the Nth array.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   assert(x.Offset<0>() == 0);   // The ints starts from 0.
    //   assert(x.Offset<1>() == 16);  // The doubles starts from 16.
    //
    // Requires: `N <= NumSizes && N < sizeof...(Ts)`.
    // ----------------------------------------------------------------------------
    template<size_t N, EnableIf<N == 0> = 0>
    constexpr size_t Offset() const {
        return 0;
    }

    template<size_t N, EnableIf<N != 0> = 0>
    constexpr size_t Offset() const {
        static_assert(N < NumOffsets, "Index out of bounds");
        return adl_barrier::Align(Offset<N - 1>() + SizeOf<ElementType<N - 1>>::value * size_[N - 1],
                                  ElementAlignment<N>::value);
    }

    // Offset in bytes of the array with the specified element type. There must
    // be exactly one such array and its zero-based index must be at most
    // `NumSizes`.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   assert(x.Offset<int>() == 0);      // The ints starts from 0.
    //   assert(x.Offset<double>() == 16);  // The doubles starts from 16.
    // ----------------------------------------------------------------------------
    template<class T>
    constexpr size_t Offset() const {
        return Offset<ElementIndex<T>()>();
    }

    // Offsets in bytes of all arrays for which the offsets are known.
    constexpr std::array<size_t, NumOffsets> Offsets() const { return { { Offset<OffsetSeq>()... } }; }

    // The number of elements in the Nth array. This is the Nth argument of
    // `Layout::Partial()` or `Layout::Layout()` (zero-based).
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   assert(x.Size<0>() == 3);
    //   assert(x.Size<1>() == 4);
    //
    // Requires: `N < NumSizes`.
    // ----------------------------------------------------------------------------
    template<size_t N>
    constexpr size_t Size() const {
        static_assert(N < NumSizes, "Index out of bounds");
        return size_[N];
    }

    // The number of elements in the array with the specified element type.
    // There must be exactly one such array and its zero-based index must be
    // at most `NumSizes`.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   assert(x.Size<int>() == 3);
    //   assert(x.Size<double>() == 4);
    // ----------------------------------------------------------------------------
    template<class T>
    constexpr size_t Size() const {
        return Size<ElementIndex<T>()>();
    }

    // The number of elements of all arrays for which they are known.
    constexpr std::array<size_t, NumSizes> Sizes() const { return { { Size<SizeSeq>()... } }; }

    // Pointer to the beginning of the Nth array.
    //
    // `Char` must be `[const] [signed|unsigned] char`.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   unsigned char* p = new unsigned char[x.AllocSize()];
    //   int* ints = x.Pointer<0>(p);
    //   double* doubles = x.Pointer<1>(p);
    //
    // Requires: `N <= NumSizes && N < sizeof...(Ts)`.
    // Requires: `p` is aligned to `Alignment()`.
    // ----------------------------------------------------------------------------
    template<size_t N, class Char>
    CopyConst<Char, ElementType<N>>* Pointer(Char* p) const {
        using C = typename std::remove_const_t<Char>;
        static_assert(std::is_same<C, char>() || std::is_same<C, unsigned char>() || std::is_same<C, signed char>(),
                      "The argument must be a pointer to [const] [signed|unsigned] char");
        constexpr size_t alignment = Alignment();
        (void)alignment;
        assert(reinterpret_cast<uintptr_t>(p) % alignment == 0);
        return reinterpret_cast<CopyConst<Char, ElementType<N>>*>(p + Offset<N>());
    }

    // Pointer to the beginning of the array with the specified element type.
    // There must be exactly one such array and its zero-based index must be at
    // most `NumSizes`.
    //
    // `Char` must be `[const] [signed|unsigned] char`.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   unsigned char* p = new unsigned char[x.AllocSize()];
    //   int* ints = x.Pointer<int>(p);
    //   double* doubles = x.Pointer<double>(p);
    //
    // Requires: `p` is aligned to `Alignment()`.
    // ----------------------------------------------------------------------------
    template<class T, class Char>
    CopyConst<Char, T>* Pointer(Char* p) const {
        return Pointer<ElementIndex<T>()>(p);
    }

    // Pointers to all arrays for which pointers are known.
    //
    // `Char` must be `[const] [signed|unsigned] char`.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   unsigned char* p = new unsigned char[x.AllocSize()];
    //
    //   int* ints;
    //   double* doubles;
    //   std::tie(ints, doubles) = x.Pointers(p);
    //
    // Requires: `p` is aligned to `Alignment()`.
    //
    // Note: We're not using ElementType alias here because it does not compile
    // under MSVC.
    // ----------------------------------------------------------------------------
    template<class Char>
    std::tuple<CopyConst<Char, typename std::tuple_element<OffsetSeq, ElementTypes>::type>*...> Pointers(
        Char* p) const {
        return std::tuple<CopyConst<Char, ElementType<OffsetSeq>>*...>(Pointer<OffsetSeq>(p)...);
    }

    // The size of the allocation that fits all arrays.
    //
    //   // int[3], 4 bytes of padding, double[4].
    //   Layout<int, double> x(3, 4);
    //   unsigned char* p = new unsigned char[x.AllocSize()];  // 48 bytes
    //
    // Requires: `NumSizes == sizeof...(Ts)`.
    // ----------------------------------------------------------------------------
    constexpr size_t AllocSize() const {
        static_assert(NumTypes == NumSizes, "You must specify sizes of all fields");
        return Offset<NumTypes - 1>() + SizeOf<ElementType<NumTypes - 1>>::value * size_[NumTypes - 1];
    }

    // If built with --config=asan, poisons padding bytes (if any) in the
    // allocation. The pointer must point to a memory block at least
    // `AllocSize()` bytes in length.
    //
    // `Char` must be `[const] [signed|unsigned] char`.
    //
    // Requires: `p` is aligned to `Alignment()`.
    // ----------------------------------------------------------------------------
    template<class Char, size_t N = NumOffsets - 1, EnableIf<N == 0> = 0>
    void PoisonPadding(const Char* p) const {
        Pointer<0>(p); // verify the requirements on `Char` and `p`
    }

    template<class Char, size_t N = NumOffsets - 1, EnableIf<N != 0> = 0>
    void PoisonPadding(const Char* p) const {
        static_assert(N < NumOffsets, "Index out of bounds");
        (void)p;
#ifdef ADDRESS_SANITIZER
        PoisonPadding<Char, N - 1>(p);
        // The `if` is an optimization. It doesn't affect the observable behaviour.
        if (ElementAlignment<N - 1>::value % ElementAlignment<N>::value) {
            size_t start = Offset<N - 1>() + SizeOf<ElementType<N - 1>>::value * size_[N - 1];
            ASAN_POISON_MEMORY_REGION(p + start, Offset<N>() - start);
        }
#endif
    }

private:
    // Arguments of `Layout::Partial()` or `Layout::Layout()`.
    size_t size_[NumSizes > 0 ? NumSizes : 1];
};

// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
template<size_t NumSizes, class... Ts>
using LayoutType = LayoutImpl<std::tuple<Ts...>,
                              std::make_index_sequence<NumSizes>,
                              std::make_index_sequence<adl_barrier::Min(sizeof...(Ts), NumSizes + 1)>>;

} // namespace internal_layout

// ---------------------------------------------------------------------------
// Descriptor of arrays of various types and sizes laid out in memory one after
// another. See the top of the file for documentation.
//
// Check out the public API of internal_layout::LayoutImpl above. The type is
// internal to the library but its methods are public, and they are inherited
// by `Layout`.
// ---------------------------------------------------------------------------
template<class... Ts>
class Layout : public internal_layout::LayoutType<sizeof...(Ts), Ts...> {
public:
    static_assert(sizeof...(Ts) > 0, "At least one field is required");
    static_assert(std::conjunction_v<internal_layout::IsLegalElementType<Ts>...>,
                  "Invalid element type (see IsLegalElementType)");

    template<size_t NumSizes>
    using PartialType = internal_layout::LayoutType<NumSizes, Ts...>;

    template<class... Sizes>
    static constexpr PartialType<sizeof...(Sizes)> Partial(Sizes&&... sizes) {
        static_assert(sizeof...(Sizes) <= sizeof...(Ts), "");
        return PartialType<sizeof...(Sizes)>(std::forward<Sizes>(sizes)...);
    }

    // Creates a layout with the sizes of all arrays specified. If you know
    // only the sizes of the first N arrays (where N can be zero), you can use
    // `Partial()` defined above. The constructor is essentially equivalent to
    // calling `Partial()` and passing in all array sizes; the constructor is
    // provided as a convenient abbreviation.
    //
    // Note: The sizes of the arrays must be specified in number of elements,
    // not in bytes.
    constexpr explicit Layout(internal_layout::TypeToSize<Ts>... sizes)
        : internal_layout::LayoutType<sizeof...(Ts), Ts...>(sizes...) {}
};

} // priv

// -----------------------------------------------------------------------
// -----------------------------------------------------------------------
template<class, class = void>
struct IsTransparent : std::false_type {};

template<class T>
struct IsTransparent<T, std::void_t<typename T::is_transparent>> : std::true_type {};

template<bool is_transparent>
struct KeyArg {
    // Transparent. Forward `K`.
    template<typename K, typename key_type>
    using type = K;
};

template<>
struct KeyArg<false> {
    // Not transparent. Always use `key_type`.
    template<typename K, typename key_type>
    using type = key_type;
};

// -----------------------------------------------------------------------
// -----------------------------------------------------------------------
template<class T>
struct EqualTo {
    inline bool operator()(const T& a, const T& b) const { return std::equal_to<T>()(a, b); }
};

template<class T>
struct Less {
    inline bool operator()(const T& a, const T& b) const { return std::less<T>()(a, b); }
};

// -----------------------------------------------------------------------
// std::aligned_storage and std::aligned_storage_t are deprecated in C++23
// -----------------------------------------------------------------------
template<std::size_t Len, std::size_t Align>
struct aligned_storage {
    struct type {
        alignas(Align) unsigned char data[Len];
    };
};

template<std::size_t Len, std::size_t Align>
using aligned_storage_t = typename aligned_storage<Len, Align>::type;

// -----------------------------------------------------------------------
// The node_handle concept from C++17.
// We specialize node_handle for sets and maps. node_handle_base holds the
// common API of both.
// -----------------------------------------------------------------------
template<typename PolicyTraits, typename Alloc>
class node_handle_base {
protected:
    using slot_type = typename PolicyTraits::slot_type;

public:
    using allocator_type = Alloc;

    constexpr node_handle_base() {}

    node_handle_base(node_handle_base&& other) noexcept { *this = std::move(other); }

    ~node_handle_base() { destroy(); }

    node_handle_base& operator=(node_handle_base&& other) noexcept {
        destroy();
        if (!other.empty()) {
            alloc_ = other.alloc_;
            PolicyTraits::transfer(alloc(), slot(), other.slot());
            other.reset();
        }
        return *this;
    }

    bool empty() const noexcept { return !alloc_; }
    explicit operator bool() const noexcept { return !empty(); }
    allocator_type get_allocator() const { return *alloc_; }

protected:
    friend struct CommonAccess;

    struct transfer_tag_t {};
    node_handle_base(transfer_tag_t, const allocator_type& a, slot_type* s)
        : alloc_(a) {
        PolicyTraits::transfer(alloc(), slot(), s);
    }

    struct move_tag_t {};
    node_handle_base(move_tag_t, const allocator_type& a, slot_type* s)
        : alloc_(a) {
        PolicyTraits::construct(alloc(), slot(), s);
    }

    node_handle_base(const allocator_type& a, slot_type* s)
        : alloc_(a) {
        PolicyTraits::transfer(alloc(), slot(), s);
    }

    // node_handle_base(const node_handle_base&) = delete;
    // node_handle_base& operator=(const node_handle_base&) = delete;

    void destroy() {
        if (!empty()) {
            PolicyTraits::destroy(alloc(), slot());
            reset();
        }
    }

    void reset() {
        assert(alloc_.has_value());
        alloc_ = std::nullopt;
    }

    slot_type* slot() const {
        assert(!empty());
        return reinterpret_cast<slot_type*>(std::addressof(slot_space_));
    }

    allocator_type* alloc() { return std::addressof(*alloc_); }

private:
    std::optional<allocator_type>                                         alloc_;
    mutable gtl::aligned_storage_t<sizeof(slot_type), alignof(slot_type)> slot_space_;
};

// For sets.
// ---------
template<typename Policy, typename PolicyTraits, typename Alloc, typename = void>
class node_handle : public node_handle_base<PolicyTraits, Alloc> {
    using Base = node_handle_base<PolicyTraits, Alloc>;

public:
    using value_type = typename PolicyTraits::value_type;

    constexpr node_handle() {}

    value_type& value() const { return PolicyTraits::element(this->slot()); }

    value_type& key() const { return PolicyTraits::element(this->slot()); }

private:
    friend struct CommonAccess;

    using Base::Base;
};

// For maps.
// ---------
template<typename Policy, typename PolicyTraits, typename Alloc>
class node_handle<Policy, PolicyTraits, Alloc, std::void_t<typename Policy::mapped_type>>
    : public node_handle_base<PolicyTraits, Alloc> {
    using Base = node_handle_base<PolicyTraits, Alloc>;

public:
    using key_type    = typename Policy::key_type;
    using mapped_type = typename Policy::mapped_type;

    constexpr node_handle() {}

    auto key() const -> decltype(PolicyTraits::key(this->slot())) { return PolicyTraits::key(this->slot()); }

    mapped_type& mapped() const { return PolicyTraits::value(&PolicyTraits::element(this->slot())); }

private:
    friend struct CommonAccess;

    using Base::Base;
};

// Provide access to non-public node-handle functions.
// ---------------------------------------------------
struct CommonAccess {
    template<typename Node>
    static auto GetSlot(const Node& node) -> decltype(node.slot()) {
        return node.slot();
    }

    template<typename Node>
    static void Destroy(Node* node) {
        node->destroy();
    }

    template<typename Node>
    static void Reset(Node* node) {
        node->reset();
    }

    template<typename T, typename... Args>
    static T Make(Args&&... args) {
        return T(std::forward<Args>(args)...);
    }

    template<typename T, typename... Args>
    static T Transfer(Args&&... args) {
        return T(typename T::transfer_tag_t{}, std::forward<Args>(args)...);
    }

    template<typename T, typename... Args>
    static T Move(Args&&... args) {
        return T(typename T::move_tag_t{}, std::forward<Args>(args)...);
    }
};

// Implement the insert_return_type<> concept of C++17.
// ----------------------------------------------------
template<class Iterator, class NodeType>
struct InsertReturnType {
    Iterator position;
    bool     inserted;
    NodeType node;
};

// ----------------------------------------------------------------------------
// If Pair is a standard-layout type, OffsetOf<Pair>::kFirst and
// OffsetOf<Pair>::kSecond are equivalent to offsetof(Pair, first) and
// offsetof(Pair, second) respectively. Otherwise they are -1.
//
// The purpose of OffsetOf is to avoid calling offsetof() on non-standard-layout
// type, which is non-portable.
// ----------------------------------------------------------------------------
template<class Pair, class = std::true_type>
struct OffsetOf {
    static constexpr size_t kFirst  = (size_t)-1;
    static constexpr size_t kSecond = (size_t)-1;
};

template<class Pair>
struct OffsetOf<Pair, typename std::is_standard_layout<Pair>::type> {
    static constexpr size_t kFirst  = offsetof(Pair, first);
    static constexpr size_t kSecond = offsetof(Pair, second);
};

// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
#ifdef _MSC_VER
    #pragma warning(push)
    // warning warning C4324: structure was padded due to alignment specifier
    #pragma warning(disable : 4324)
#endif

// ----------------------------------------------------------------------------
// Allocates at least n bytes aligned to the specified alignment.
// Alignment must be a power of 2. It must be positive.
//
// Note that many allocators don't honor alignment requirements above certain
// threshold (usually either alignof(std::max_align_t) or alignof(void*)).
// Allocate() doesn't apply alignment corrections. If the underlying allocator
// returns insufficiently alignment pointer, that's what you are going to get.
// ----------------------------------------------------------------------------
template<size_t Alignment, class Alloc>
void* Allocate(Alloc* alloc, size_t n) {
    static_assert(Alignment > 0, "");
    assert(n && "n must be positive");
    struct alignas(Alignment) M {};
    using A  = typename std::allocator_traits<Alloc>::template rebind_alloc<M>;
    using AT = typename std::allocator_traits<Alloc>::template rebind_traits<M>;
    A     mem_alloc(*alloc);
    // `&*` below to support custom pointers such as boost offset_ptr.
    void* p = &*AT::allocate(mem_alloc, (n + sizeof(M) - 1) / sizeof(M));
    assert(reinterpret_cast<uintptr_t>(p) % Alignment == 0 && "allocator does not respect alignment");
    return p;
}

// ----------------------------------------------------------------------------
// The pointer must have been previously obtained by calling
// Allocate<Alignment>(alloc, n).
// ----------------------------------------------------------------------------
template<size_t Alignment, class Alloc>
void Deallocate(Alloc* alloc, void* p, size_t n) {
    static_assert(Alignment > 0, "");
    assert(n && "n must be positive");
    struct alignas(Alignment) M {};
    using A  = typename std::allocator_traits<Alloc>::template rebind_alloc<M>;
    using AT = typename std::allocator_traits<Alloc>::template rebind_traits<M>;
    A mem_alloc(*alloc);
    AT::deallocate(mem_alloc, static_cast<M*>(p), (n + sizeof(M) - 1) / sizeof(M));
}

#ifdef _MSC_VER
    #pragma warning(pop)
#endif

// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
#ifdef ADDRESS_SANITIZER
    #include <sanitizer/asan_interface.h>
#endif

inline void SanitizerPoisonMemoryRegion(const void* m, size_t s) {
#ifdef ADDRESS_SANITIZER
    ASAN_POISON_MEMORY_REGION(m, s);
#endif
#ifdef MEMORY_SANITIZER
    __msan_poison(m, s);
#endif
    (void)m;
    (void)s;
}

inline void SanitizerUnpoisonMemoryRegion(const void* m, size_t s) {
#ifdef ADDRESS_SANITIZER
    ASAN_UNPOISON_MEMORY_REGION(m, s);
#endif
#ifdef MEMORY_SANITIZER
    __msan_unpoison(m, s);
#endif
    (void)m;
    (void)s;
}

template<typename T>
inline void SanitizerPoisonObject(const T* object) {
    SanitizerPoisonMemoryRegion(object, sizeof(T));
}

template<typename T>
inline void SanitizerUnpoisonObject(const T* object) {
    SanitizerUnpoisonMemoryRegion(object, sizeof(T));
}

namespace {
#ifdef GTL_HAVE_EXCEPTIONS
  #define GTL_THROW_IMPL_MSG(e, message) throw e(message)
  #define GTL_THROW_IMPL(e) throw e()
#else
  #define GTL_THROW_IMPL_MSG(e, message) do { (void)(message); std::abort(); } while(0)
  #define GTL_THROW_IMPL(e) std::abort()
#endif
} // namespace


static inline void ThrowStdOutOfRange(const std::string& what_arg) { GTL_THROW_IMPL_MSG(std::out_of_range, what_arg); }
static inline void ThrowStdOutOfRange(const char* what_arg) { GTL_THROW_IMPL_MSG(std::out_of_range, what_arg); }

} // gtl

#ifdef _MSC_VER
    #pragma warning(pop)
#endif

#endif // gtl_base_hpp_guard_
