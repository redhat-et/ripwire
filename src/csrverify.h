#pragma once

#include "sparseCsr.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace rw
{

template<class T>
inline bool verifyCsr( const sparseCsr<T>& csr, std::size_t nodeCount ) noexcept
{
    if( csr.rows() != nodeCount || csr.cols() != nodeCount || csr.nnz() > std::numeric_limits<std::uint32_t>::max() )
        return false;

    const std::uint32_t* rowOffsets = csr.rowOffsets();
    const std::uint32_t* columnIndices = csr.colIndices();
    const T* values = csr.values();
    if( rowOffsets == nullptr || ( csr.nnz() != 0 && ( columnIndices == nullptr || values == nullptr ) ) )
        return false;
    if( rowOffsets[0] != 0 || std::size_t( rowOffsets[nodeCount] ) != csr.nnz() )
        return false;

    for( std::size_t rowIndex = 0; rowIndex < nodeCount; ++rowIndex )
    {
        if( rowOffsets[rowIndex] > rowOffsets[rowIndex + 1] || std::size_t( rowOffsets[rowIndex + 1] ) > csr.nnz() )
            return false;
    }
    for( std::size_t edgeIndex = 0; edgeIndex < csr.nnz(); ++edgeIndex )
    {
        if( columnIndices[edgeIndex] >= nodeCount || !std::isfinite( values[edgeIndex] ) || values[edgeIndex] < T( 0 ) )
            return false;
    }
    return true;
}

} // namespace rw
