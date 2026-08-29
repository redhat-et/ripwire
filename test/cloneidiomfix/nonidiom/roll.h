#pragma once
namespace two
{

inline int rollupSamples( const int* samples, int span )
{
    int carry = 0;
    for( int k = 0; k < span; ++k )
    {
        carry += samples[k];
        carry ^= ( carry << 1 );
        carry -= k;
    }
    return carry;
}

}   // namespace two
