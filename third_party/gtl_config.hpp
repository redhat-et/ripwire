#ifndef gtl_config_hpp_guard_
#define gtl_config_hpp_guard_

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

#define GTL_VERSION_MAJOR 1
#define GTL_VERSION_MINOR 2
#define GTL_VERSION_PATCH 0

// Included for the __GLIBC__ macro (or similar macros on other systems).
#include <limits.h>
#include <new>

#ifdef __cplusplus
    // Included for __GLIBCXX__, _LIBCPP_VERSION
    #include <cstddef>
#endif // __cplusplus

// -----------------------------------------------------------------------------
// Some sanity checks
// -----------------------------------------------------------------------------
#if defined(_MSC_FULL_VER) && _MSC_FULL_VER < 192930139 && !defined(__clang__)
    #error "gtl requires Visual Studio 2015 Update 2 or higher."
#endif

// We support gcc 8 and later.
#if defined(__GNUC__) && !defined(__clang__)
    #if __GNUC__ < 8
        #error "gtl requires gcc 8 or higher."
    #endif
#endif

// We support Apple Xcode clang 4.2.1 (version 421.11.65) and later.
// This corresponds to Apple Xcode version 4.5.
#if defined(__apple_build_version__) && __apple_build_version__ < 4211165
    #error "gtl requires __apple_build_version__ of 4211165 or higher."
#endif

// Enforce C++11 as the minimum.
#if defined(__cplusplus) && !defined(_MSC_VER)
    #if __cplusplus < 201402L
        #error "C++ versions less than C++20 are not supported."
    #endif
#endif

// We have chosen glibc 2.12 as the minimum
#if defined(__GLIBC__) && defined(__GLIBC_PREREQ)
    #if !__GLIBC_PREREQ(2, 12)
        #error "Minimum required version of glibc is 2.12."
    #endif
#endif

#if defined(_STLPORT_VERSION)
    #error "STLPort is not supported."
#endif

#if CHAR_BIT != 8
    #warning "gtl assumes CHAR_BIT == 8."
#endif

// gtl currently assumes that an int is 4 bytes.
#if INT_MAX < 2147483647
    #error "gtl assumes that int is at least 4 bytes. "
#endif

// -----------------------------------------------------------------------------
// Compiler Feature Checks
// -----------------------------------------------------------------------------

#ifdef __has_builtin
    #define GTL_HAVE_BUILTIN(x) __has_builtin(x)
#else
    #define GTL_HAVE_BUILTIN(x) 0
#endif

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
#if defined(__cpp_lib_three_way_comparison)
    #define GTL_HAS_COMPARE 1
#else
    #define GTL_HAS_COMPARE 0
#endif

// ------------------------------------------------------------
// Checks whether the __int128 compiler extension for a 128-bit
// integral type is supported.
// ------------------------------------------------------------
#ifdef GTL_HAVE_INTRINSIC_INT128
    #error GTL_HAVE_INTRINSIC_INT128 cannot be directly set
#elif defined(__SIZEOF_INT128__)
    #if (defined(__clang__) && !defined(_WIN32) && !defined(__aarch64__)) ||                                           \
        (defined(__CUDACC__) && __CUDACC_VER_MAJOR__ >= 9) ||                                                          \
        (defined(__GNUC__) && !defined(__clang__) && !defined(__CUDACC__))
        #define GTL_HAVE_INTRINSIC_INT128 1
    #elif defined(__CUDACC__)
        #if __CUDACC_VER__ >= 70000
            #define GTL_HAVE_INTRINSIC_INT128 1
        #endif // __CUDACC_VER__ >= 70000
    #endif     // defined(__CUDACC__)
#endif

// -----------------------------------------------------------------------
// Checks the endianness of the platform.
// -----------------------------------------------------------------------
#if defined(GTL_IS_BIG_ENDIAN)
    #error "GTL_IS_BIG_ENDIAN cannot be directly set."
#endif

#if defined(GTL_IS_LITTLE_ENDIAN)
    #error "GTL_IS_LITTLE_ENDIAN cannot be directly set."
#endif

#if (defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    #define GTL_IS_LITTLE_ENDIAN 1
#elif defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    #define GTL_IS_BIG_ENDIAN 1
#elif defined(_WIN32)
    #define GTL_IS_LITTLE_ENDIAN 1
#else
    #error "gtl endian detection needs to be set up for your compiler"
#endif

// ------------------------------------------------------------------
// Checks whether the compiler both supports and enables exceptions.
// ------------------------------------------------------------------
#ifdef GTL_HAVE_EXCEPTIONS
    #error GTL_HAVE_EXCEPTIONS cannot be directly set.
#elif defined(__clang__)
    #if defined(__EXCEPTIONS) && __has_feature(cxx_exceptions)
        #define GTL_HAVE_EXCEPTIONS 1
    #endif // defined(__EXCEPTIONS) && __has_feature(cxx_exceptions)
#elif !(defined(__GNUC__) && (__GNUC__ < 5) && !defined(__EXCEPTIONS)) &&                                              \
    !(defined(__GNUC__) && (__GNUC__ >= 5) && !defined(__cpp_exceptions)) &&                                           \
    !(defined(_MSC_VER) && !defined(_CPPUNWIND))
    #define GTL_HAVE_EXCEPTIONS 1
#endif

// ---------------------------------------------------------------------------
// Checks whether wchar_t is treated as a native type
// (MSVC: /Zc:wchar_t- treats wchar_t as unsigned short)
// ---------------------------------------------------------------------------
#if !defined(_MSC_VER) || defined(_NATIVE_WCHAR_T_DEFINED)
    #define GTL_HAS_NATIVE_WCHAR_T
#endif

// -----------------------------------------------------------------------------
// A function-like feature checking macro that is a wrapper around
// `__has_attribute`, which is defined by GCC 5+ and Clang and evaluates to a
// nonzero constant integer if the attribute is supported or 0 if not.
//
// It evaluates to zero if `__has_attribute` is not defined by the compiler.
// -----------------------------------------------------------------------------
#ifdef __has_attribute
    #define GTL_HAVE_ATTRIBUTE(x) __has_attribute(x)
#else
    #define GTL_HAVE_ATTRIBUTE(x) 0
#endif

// -----------------------------------------------------------------------------
// A function-like feature checking macro that accepts C++11 style attributes.
// It's a wrapper around `__has_cpp_attribute`, defined by ISO C++ SD-6
// (https://en.cppreference.com/w/cpp/experimental/feature_test). If we don't
// find `__has_cpp_attribute`, will evaluate to 0.
// -----------------------------------------------------------------------------
#if defined(__cplusplus) && defined(__has_cpp_attribute)
    #define GTL_HAVE_CPP_ATTRIBUTE(x) __has_cpp_attribute(x)
#else
    #define GTL_HAVE_CPP_ATTRIBUTE(x) 0
#endif

// -----------------------------------------------------------------------------
// Function Attributes
// -----------------------------------------------------------------------------
#if GTL_HAVE_ATTRIBUTE(always_inline) || (defined(__GNUC__) && !defined(__clang__))
    #define GTL_ATTRIBUTE_ALWAYS_INLINE __attribute__((always_inline))
    #define GTL_HAVE_ATTRIBUTE_ALWAYS_INLINE 1
#else
    #define GTL_ATTRIBUTE_ALWAYS_INLINE
#endif

#if !defined(__INTEL_COMPILER) && (GTL_HAVE_ATTRIBUTE(noinline) || (defined(__GNUC__) && !defined(__clang__)))
    #define GTL_ATTRIBUTE_NOINLINE __attribute__((noinline))
    #define GTL_HAVE_ATTRIBUTE_NOINLINE 1
#else
    #define GTL_ATTRIBUTE_NOINLINE
#endif

#if defined(__clang__)
    #if GTL_HAVE_CPP_ATTRIBUTE(clang::reinitializes)
        #define GTL_ATTRIBUTE_REINITIALIZES [[clang::reinitializes]]
    #else
        #define GTL_ATTRIBUTE_REINITIALIZES
    #endif
#else
    #define GTL_ATTRIBUTE_REINITIALIZES
#endif

#if defined(_MSC_VER) && _MSC_VER >= 1929
    #define GTL_ATTRIBUTE_NO_UNIQUE_ADDRESS [[msvc::no_unique_address]]
#elif GTL_HAVE_ATTRIBUTE(no_unique_address) || GTL_HAVE_CPP_ATTRIBUTE(no_unique_address)
    #define GTL_ATTRIBUTE_NO_UNIQUE_ADDRESS [[no_unique_address]]
#else
    #define GTL_ATTRIBUTE_NO_UNIQUE_ADDRESS
#endif

#if GTL_HAVE_ATTRIBUTE(assume)
    #define GTL_ASSUME(expr) [[assume(expr)]]
#elif defined(__clang__)
    #define GTL_ASSUME(expr) __builtin_assume(expr)
#elif defined(_MSC_VER) || defined(__ICC)
    #define GTL_ASSUME(expr) __assume(expr)
#else
    #define GTL_ASSUME(expr)
#endif

// ----------------------------------------------------------------------
// Figure out SSE support
// ----------------------------------------------------------------------
#ifndef GTL_HAVE_SSE2
    #if defined(__SSE2__) || (defined(_MSC_VER) && (defined(_M_X64) || (defined(_M_IX86) && _M_IX86_FP >= 2)))
        #define GTL_HAVE_SSE2 1
    #else
        #define GTL_HAVE_SSE2 0
    #endif
#endif

#ifndef GTL_HAVE_SSSE3
    #if defined(__SSSE3__) || defined(__AVX2__)
        #define GTL_HAVE_SSSE3 1
    #else
        #define GTL_HAVE_SSSE3 0
    #endif
#endif

#if GTL_HAVE_SSSE3 && !GTL_HAVE_SSE2
    #error "Bad configuration!"
#endif

#if GTL_HAVE_SSE2
    #include <emmintrin.h>
#endif

#if GTL_HAVE_SSSE3
    #include <tmmintrin.h>
#endif

// ----------------------------------------------------------------------
// RESTRICT
// ----------------------------------------------------------------------
#if (defined(__GNUC__) && (__GNUC__ > 3)) || defined(__clang__)
    #define GTL_RESTRICT __restrict__
#elif defined(_MSC_VER) && _MSC_VER >= 1400
    #define GTL_RESTRICT __restrict
#else
    #define GTL_RESTRICT
#endif

// ----------------------------------------------------------------------
// define gtl_hardware_destructive_interference_size
// ----------------------------------------------------------------------
#ifdef __cpp_lib_hardware_interference_size
    #define gtl_hardware_destructive_interference_size std::hardware_destructive_interference_size
#else
    #define gtl_hardware_destructive_interference_size 64
#endif

#endif // gtl_config_hpp_guard_
