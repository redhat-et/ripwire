#pragma once
#include "grade.h"
namespace beta
{

inline shared::Grade gradeOfScore( float score )
{
    if( score < 25.0f ) return shared::Grade::Poor;
    if( score < 55.0f ) return shared::Grade::Fair;
    if( score < 85.0f ) return shared::Grade::Good;
    return shared::Grade::Great;
}

}   // namespace beta
