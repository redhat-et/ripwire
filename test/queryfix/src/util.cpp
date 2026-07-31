struct Gadget { int g; };
int hot() { int s = 0; for( int i = 0; i < 8; ++i ) { if( i % 2 ) s += i; else s -= i; } return s; }
int caller_a() { return hot(); }
int caller_b() { return hot(); }
int rec( int n ) { return n > 0 ? rec( n - 1 ) : 0; }
