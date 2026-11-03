#include "build.h"
int Builder::Run( int p ) { return disk_->ReadFile( p ) + 2; }
