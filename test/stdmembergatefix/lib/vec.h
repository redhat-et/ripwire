#pragma once
#include <cstddef>

template<class T> struct Vec
{
    T*          d = nullptr;
    std::size_t n = 0;
    void        push_back( const T& v ) { grow(); d[ n++ ] = v; }
    void        push_back( T&& v ) { grow(); d[ n++ ] = v; }
    std::size_t size() const { return n; }
    bool        empty() const { return n == 0; }
    void        clear() { n = 0; }
    T*          data() { return d; }
    void        grow() {}
    void        pushTwice( const T& v ) { push_back( v ); this->push_back( v ); }
};

struct Pool
{
    std::size_t size() const { return 3; }
    bool        empty() const { return false; }
    void        clear() {}
};

struct Solo
{
    void append( int ) {}
};

struct Bag
{
    int k = 0;
};
inline std::size_t size( const Bag& b ) { return std::size_t( b.k ); }
