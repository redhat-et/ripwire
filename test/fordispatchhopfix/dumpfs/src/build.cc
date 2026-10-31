#include "disk.h"
struct Builder { Disk* disk_; int Run( int p ); };
int Builder::Run( int p ) { return disk_->ReadFile( p ) + 2; }
int main() { RealDisk d; Builder b{ &d }; return b.Run( 4 ); }
