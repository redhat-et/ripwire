// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  structlayout.h
//
//  Cross-translation-unit layout tripwire. Every translation unit that includes
//  this header registers the sizeof/alignof facts it compiled with. The registry
//  is intentionally separate from src/layout.h: that file models source text for
//  repositories ripwire analyzes, while this file records this binary's ABI view.
//
//  The records have internal linkage. Only the registry and its registrar are
//  shared, so an inline record cannot make the linker discard one TU's evidence.
//
#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

#if defined( __GNUC__ ) || defined( __clang__ )
#define RIPWIRE_LAYOUT_USED __attribute__( ( used ) )
#else
#define RIPWIRE_LAYOUT_USED
#endif

// __FILE__ expands to this header at the registration site. GCC and Clang's
// __BASE_FILE__ is the primary source file passed to the compiler, which is the
// identity needed here. A build system can override it for a compiler without
// __BASE_FILE__ (and for fixture tests that compile one source twice).
#if !defined( RIPWIRE_LAYOUT_TU )
#if defined( __BASE_FILE__ )
#define RIPWIRE_LAYOUT_TU __BASE_FILE__
#else
#error "RIPWIRE_LAYOUT_TU must be supplied when __BASE_FILE__ is unavailable"
#endif
#endif

namespace rw
{
namespace layout_registry
{

struct TypeLayout
{
    const char* name  = nullptr;
    std::size_t size  = 0;
    std::size_t align = 0;
};

struct LayoutRecord
{
    const char*           unit      = nullptr;
    const TypeLayout*     types     = nullptr;
    std::size_t           typeCount = 0;
};

class Registry
{
public:
    void add( const LayoutRecord* record )
    {
        records_.push_back( record );
    }

    const std::vector<const LayoutRecord*>& records() const noexcept
    {
        return records_;
    }

private:
    std::vector<const LayoutRecord*> records_;
};

// Function-local construction keeps registration independent of the order in
// which static initializers from different translation units run.
inline Registry& registry()
{
    static Registry instance;
    return instance;
}

class Registrar
{
public:
    explicit Registrar( const LayoutRecord& record )
    {
        registry().add( &record );
    }
};

enum class CheckState : std::uint8_t
{
    NoRecords,
    NotChecked,
    Agree,
    Disagree,
};

struct LayoutMismatch
{
    const char* typeName = nullptr;
    const char* unit0    = nullptr;
    const char* unit1    = nullptr;
    std::size_t size0    = 0;
    std::size_t size1    = 0;
    std::size_t align0   = 0;
    std::size_t align1   = 0;
    bool        present0 = false;
    bool        present1 = false;
};

struct LayoutCheck
{
    CheckState    state     = CheckState::NoRecords;
    std::size_t   unitCount = 0;
    std::size_t   typeCount = 0;
    LayoutMismatch mismatch;
};

inline const TypeLayout* findType( const LayoutRecord& record, const char* name ) noexcept
{
    for( std::size_t i = 0; i < record.typeCount; ++i )
    {
        if( std::strcmp( record.types[ i ].name, name ) == 0 )
        {
            return &record.types[ i ];
        }
    }
    return nullptr;
}

inline std::vector<const LayoutRecord*> sortedRecords()
{
    std::vector<const LayoutRecord*> records = registry().records();
    std::sort( records.begin(), records.end(), []( const LayoutRecord* left, const LayoutRecord* right )
    {
        return std::strcmp( left->unit, right->unit ) < 0;
    } );
    return records;
}

inline LayoutCheck disagreement( const LayoutRecord& first, const TypeLayout* firstType,
                                 const LayoutRecord& second, const TypeLayout* secondType,
                                 const char* typeName ) noexcept
{
    LayoutCheck result;
    result.state     = CheckState::Disagree;
    result.unitCount = 2;
    result.typeCount = first.typeCount;
    result.mismatch  = { typeName,
                         first.unit,
                         second.unit,
                         firstType != nullptr ? firstType->size : 0,
                         secondType != nullptr ? secondType->size : 0,
                         firstType != nullptr ? firstType->align : 0,
                         secondType != nullptr ? secondType->align : 0,
                         firstType != nullptr,
                         secondType != nullptr };
    return result;
}

inline LayoutCheck compare()
{
    const std::vector<const LayoutRecord*> records = sortedRecords();
    LayoutCheck result;
    result.unitCount = records.size();

    if( records.empty() )
    {
        return result;
    }
    result.typeCount = records.front()->typeCount;
    if( records.size() == 1 )
    {
        result.state = CheckState::NotChecked;
        return result;
    }

    bool hasType = false;
    for( const LayoutRecord* record : records )
    {
        hasType = hasType || record->typeCount != 0;
    }
    if( !hasType )
    {
        result.state = CheckState::NotChecked;
        return result;
    }

    const LayoutRecord& first = *records.front();
    for( std::size_t typeIndex = 0; typeIndex < first.typeCount; ++typeIndex )
    {
        const TypeLayout& expected = first.types[ typeIndex ];
        for( std::size_t unitIndex = 1; unitIndex < records.size(); ++unitIndex )
        {
            const LayoutRecord& actualRecord = *records[ unitIndex ];
            const TypeLayout*   actual       = findType( actualRecord, expected.name );
            if( actual == nullptr || actual->size != expected.size || actual->align != expected.align )
            {
                LayoutCheck mismatch = disagreement( first, &expected, actualRecord, actual, expected.name );
                mismatch.unitCount = records.size();
                return mismatch;
            }
        }
    }

    // A record with an extra type is also a disagreement. The fixed model list
    // should never take this path, but it keeps the registry honest for tests
    // and for future additions to the recorded aggregate set.
    for( std::size_t unitIndex = 1; unitIndex < records.size(); ++unitIndex )
    {
        const LayoutRecord& actualRecord = *records[ unitIndex ];
        for( std::size_t typeIndex = 0; typeIndex < actualRecord.typeCount; ++typeIndex )
        {
            const TypeLayout& actual = actualRecord.types[ typeIndex ];
            if( findType( first, actual.name ) == nullptr )
            {
                LayoutCheck mismatch = disagreement( first, nullptr, actualRecord, &actual, actual.name );
                mismatch.unitCount = records.size();
                return mismatch;
            }
        }
    }

    result.state = CheckState::Agree;
    return result;
}

}   // namespace layout_registry
}   // namespace rw

#define RIPWIRE_LAYOUT_TYPE_ENTRY( Type ) { #Type, sizeof( Type ), alignof( Type ) }
#define RIPWIRE_LAYOUT_DETAIL_JOIN_IMPL( left, right ) left##right
#define RIPWIRE_LAYOUT_DETAIL_JOIN( left, right ) RIPWIRE_LAYOUT_DETAIL_JOIN_IMPL( left, right )
#define RIPWIRE_LAYOUT_DETAIL_REGISTER( id, ... )                                      \
    namespace                                                                            \
    {                                                                                    \
        RIPWIRE_LAYOUT_USED static const ::rw::layout_registry::TypeLayout               \
            RIPWIRE_LAYOUT_DETAIL_JOIN( kRipwireLayoutTypes, id )[] = { __VA_ARGS__ };  \
        RIPWIRE_LAYOUT_USED static const ::rw::layout_registry::LayoutRecord             \
            RIPWIRE_LAYOUT_DETAIL_JOIN( kRipwireLayoutRecord, id ) = {                   \
                RIPWIRE_LAYOUT_TU,                                                        \
                RIPWIRE_LAYOUT_DETAIL_JOIN( kRipwireLayoutTypes, id ),                    \
                sizeof( RIPWIRE_LAYOUT_DETAIL_JOIN( kRipwireLayoutTypes, id ) )            \
                    / sizeof( ::rw::layout_registry::TypeLayout ) };                      \
        RIPWIRE_LAYOUT_USED static const ::rw::layout_registry::Registrar                 \
            RIPWIRE_LAYOUT_DETAIL_JOIN( kRipwireLayoutRegistrar, id )(                    \
                RIPWIRE_LAYOUT_DETAIL_JOIN( kRipwireLayoutRecord, id ) );                 \
    }
#define RIPWIRE_LAYOUT_REGISTER_TYPES( ... ) RIPWIRE_LAYOUT_DETAIL_REGISTER( __COUNTER__, __VA_ARGS__ )
