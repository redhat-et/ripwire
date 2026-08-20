// Every `Widget` below is a TYPE POSITION and nothing else: a member type, a return type, a parameter
// type, a template argument, and a local declaration type. There is no call `Widget(...)`, no
// constructor invocation with arguments, and no read or write of a value named `Widget`.
#include "a.h"

#include <vector>

struct Holder
{
    Widget m_w;
};

Widget makeOne( Widget in )
{
    return in;
}

void takeList( std::vector<Widget>& xs )
{
    (void) xs;
}

int sumOne( const Widget* p )
{
    return p != nullptr ? p->v : 0;
}
