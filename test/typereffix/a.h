// The type under test. It is a pure DATA type: nothing here is ever called or constructed by b.cpp,
// so every mention of `Widget` in that file is a bare TYPE mention and nothing else.
#pragma once

struct Widget
{
    int v;
};

struct Unrelated
{
    int w;
};
