#pragma once
#include "grade.h"
// A threshold ladder that DOES share domain identifiers with its twin below (Grade, score, and every band
// name). That is a real copy-paste, so the conjunction must refuse to demote it however well the shape
// classifies.
namespace alpha
{

inline shared::Grade gradeOfScore( float score )
{
    if( score < 30.0f ) return shared::Grade::Poor;
    if( score < 60.0f ) return shared::Grade::Fair;
    if( score < 90.0f ) return shared::Grade::Good;
    return shared::Grade::Great;
}

}   // namespace alpha
