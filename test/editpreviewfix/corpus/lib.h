#pragma once

// scale — a PUBLIC contract: it lives in a header, so isPublicApi() answers true for it.
inline int scale( int x, int k )
{
    return x * k;
}

class Box
{
public:
    int width( int pad )
    {
        return pad + 1;
    }

    int height()
    {
        return 2;
    }
};
