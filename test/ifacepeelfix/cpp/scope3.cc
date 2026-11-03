#include "scope3.h"
namespace d1 {
BaseOol::~BaseOol() {}
int BaseOol::act( int x ) { return x; }
int OolA::act( int x ) { return x + 1; }
int OolB::act( int x ) { return x + 2; }
int UsesOol::go( int x ) { return b_->act( x ); }
}
