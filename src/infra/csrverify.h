#pragma once

#include "sparseCsr.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <span>

namespace rw
{

template<class T>
inline bool verifyCsr( const sparseCsr<T>& csr, std::size_t nodeCount ) noexcept
{
    if( csr.rows() != nodeCount || csr.cols() != nodeCount || csr.nnz() > std::numeric_limits<std::uint32_t>::max() )
    {
        return false;
    }

    const std::uint32_t* rowOffsets = csr.rowOffsets();
    const std::uint32_t* columnIndices = csr.colIndices();
    const T* values = csr.values();
    if( rowOffsets == nullptr || ( csr.nnz() != 0 && ( columnIndices == nullptr || values == nullptr ) ) )
    {
        return false;
    }
    if( rowOffsets[0] != 0 || std::size_t( rowOffsets[nodeCount] ) != csr.nnz() )
    {
        return false;
    }

    for( std::size_t rowIndex = 0; rowIndex < nodeCount; ++rowIndex )
    {
        if( rowOffsets[rowIndex] > rowOffsets[rowIndex + 1] || std::size_t( rowOffsets[rowIndex + 1] ) > csr.nnz() )
        {
            return false;
        }
    }
    for( std::size_t edgeIndex = 0; edgeIndex < csr.nnz(); ++edgeIndex )
    {
        if( columnIndices[edgeIndex] >= nodeCount || !std::isfinite( values[edgeIndex] ) || values[edgeIndex] < T( 0 ) )
        {
            return false;
        }
    }
    return true;
}

// The offsets-only CSR: rows of column ids with no values and no square shape, such as the graph's distinct declined
// candidate lists (graph.h internDeclinedList). The same structural gate as verifyCsr: rowCount + 1 offsets that start at 0,
// never decrease and end at the entry count, and every column id below columnBound.
inline bool verifyOffsetCsr( std::span<const std::uint32_t> rowOffsets, std::span<const std::uint32_t> columnIndices, std::size_t rowCount,
                             std::size_t columnBound ) noexcept
{
    if( rowOffsets.size() != rowCount + 1 || columnIndices.size() > std::numeric_limits<std::uint32_t>::max() )
    {
        return false;
    }
    if( rowOffsets[0] != 0 || std::size_t( rowOffsets[rowCount] ) != columnIndices.size() )
    {
        return false;
    }

    for( std::size_t rowIndex = 0; rowIndex < rowCount; ++rowIndex )
    {
        if( rowOffsets[rowIndex] > rowOffsets[rowIndex + 1] )
        {
            return false;
        }
    }
    for( const std::uint32_t columnIndex : columnIndices )
    {
        if( columnIndex >= columnBound )
        {
            return false;
        }
    }
    return true;
}

} // namespace rw
