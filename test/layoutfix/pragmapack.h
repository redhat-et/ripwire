#pragma once

// pragmapack.h — `#pragma pack` is a FILE-SCOPED, push/pop-structured directive. Tracking its regions
// lexically is exactly the half-right preprocessing this module refuses to do, so its mere presence
// withdraws the numbers for every aggregate defined in the file.
#pragma pack( push, 1 )

struct PragmaPackedCase
{
    char  a;
    int   b;
};

#pragma pack( pop )
