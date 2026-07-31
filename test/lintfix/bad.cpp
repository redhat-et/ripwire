// lint-fixture: one clear instance of each new S6-A lint check.
// This file intentionally contains code that triggers the new lint rules;
// it is NOT production code — do NOT run it, just parse it.

#include <stdexcept>

// ── typedef-over-using ──────────────────────────────────────────────────────
// A C-style typedef struct {} in a C++ file (should use "using T = ...")
typedef struct Point2D { float x; float y; } Point2D;

// ── magic-number ────────────────────────────────────────────────────────────
// numeric literals that are not in a const/constexpr initializer
int magicFunc( int n )
{
    int result = n * 42;          // magic: 42
    if( n > 100 )                 // magic: 100
        result += 7;              // magic: 7
    return result;
}

// ── empty-catch ─────────────────────────────────────────────────────────────
// catch block with no body (swallowed exception)
void emptyCatchFunc( int x )
{
    try
    {
        int y = 1 / x;
        (void)y;
    }
    catch( ... )
    {
    }
}

// ── self-assignment ──────────────────────────────────────────────────────────
// x = x — always a bug
void selfAssignFunc( int a )
{
    a = a;                         // self-assign: a = a
}

// ── inconsistent-return ──────────────────────────────────────────────────────
// function with both `return val` and bare `return` — intent ambiguity
int inconsistentReturn( int n )
{
    if( n < 0 )
        return;              // bare return from a non-void function
    return n * 2;
}

// ── deep-nesting (depth > 4) ─────────────────────────────────────────────────
void deepNestFunc( int a, int b, int c, int d, int e )
{
    if( a )               // depth 1
    {
        if( b )           // depth 2
        {
            if( c )       // depth 3
            {
                if( d )   // depth 4
                {
                    if( e )  // depth 5  ← exceeds threshold
                    {
                        int x = a + b + c + d + e;
                        (void)x;
                    }
                }
            }
        }
    }
}

// ── large-function (body > 80 lines) ─────────────────────────────────────────
// A function body with more than 80 lines so the large-function check fires.
int largeFunctionFixture( int n )
{
    int a  = n + 1;  // line 1
    int b  = n + 2;  // line 2
    int c  = n + 3;  // line 3
    int d  = n + 4;  // line 4
    int e  = n + 5;  // line 5
    int f  = n + 6;  // line 6
    int g  = n + 7;  // line 7
    int h  = n + 8;  // line 8
    int i  = n + 9;  // line 9
    int j  = n + 10; // line 10
    int k  = n + 11; // line 11
    int l  = n + 12; // line 12
    int m  = n + 13; // line 13
    int p  = n + 14; // line 14
    int q  = n + 15; // line 15
    int r  = n + 16; // line 16
    int s  = n + 17; // line 17
    int t  = n + 18; // line 18
    int u  = n + 19; // line 19
    int v  = n + 20; // line 20
    int w  = n + 21; // line 21
    int x  = n + 22; // line 22
    int y  = n + 23; // line 23
    int z  = n + 24; // line 24
    int aa = n + 25; // line 25
    int ab = n + 26; // line 26
    int ac = n + 27; // line 27
    int ad = n + 28; // line 28
    int ae = n + 29; // line 29
    int af = n + 30; // line 30
    int ag = n + 31; // line 31
    int ah = n + 32; // line 32
    int ai = n + 33; // line 33
    int aj = n + 34; // line 34
    int ak = n + 35; // line 35
    int al = n + 36; // line 36
    int am = n + 37; // line 37
    int an = n + 38; // line 38
    int ao = n + 39; // line 39
    int ap = n + 40; // line 40
    int aq = n + 41; // line 41
    int ar = n + 42; // line 42
    int as_ = n + 43; // line 43
    int at = n + 44; // line 44
    int au = n + 45; // line 45
    int av = n + 46; // line 46
    int aw = n + 47; // line 47
    int ax = n + 48; // line 48
    int ay = n + 49; // line 49
    int az = n + 50; // line 50
    int ba = n + 51; // line 51
    int bb = n + 52; // line 52
    int bc = n + 53; // line 53
    int bd = n + 54; // line 54
    int be = n + 55; // line 55
    int bf = n + 56; // line 56
    int bg = n + 57; // line 57
    int bh = n + 58; // line 58
    int bi = n + 59; // line 59
    int bj = n + 60; // line 60
    int bk = n + 61; // line 61
    int bl = n + 62; // line 62
    int bm = n + 63; // line 63
    int bn = n + 64; // line 64
    int bo = n + 65; // line 65
    int bp = n + 66; // line 66
    int bq = n + 67; // line 67
    int br = n + 68; // line 68
    int bs = n + 69; // line 69
    int bt = n + 70; // line 70
    int bu = n + 71; // line 71
    int bv = n + 72; // line 72
    int bw = n + 73; // line 73
    int bx = n + 74; // line 74
    int by = n + 75; // line 75
    int bz = n + 76; // line 76
    int ca = n + 77; // line 77
    int cb = n + 78; // line 78
    int cc = n + 79; // line 79
    int cd = n + 80; // line 80
    int ce = n + 81; // line 81  (this is line 81 of the body — above the 80-line threshold)
    return a + b + c + d + e + f + g + h + i + j + k + l + m + p + q + r + s + t + u + v + w + x + y + z + aa + ab + ac + ad + ae + af + ag + ah + ai + aj + ak + al + am + an + ao + ap + aq + ar + as_ + at + au + av + aw + ax + ay + az + ba + bb + bc + bd + be + bf + bg + bh + bi + bj + bk + bl + bm + bn + bo + bp + bq + br + bs + bt + bu + bv + bw + bx + by + bz + ca + cb + cc + cd + ce;
}
