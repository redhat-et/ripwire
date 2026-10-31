struct Disk { virtual ~Disk(){} virtual int ReadFile( int p ) = 0; };
struct RealDisk : Disk { int ReadFile( int p ) override; };
