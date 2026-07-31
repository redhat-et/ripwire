// padding symbols with ZERO query-term overlap — they sort FIRST (file name "apad") so the plain
// lexical ranking's zero-score id-tiebreak fills its tail slots from HERE, never from queue.cpp.
int parseHeaderLine( int x ) { return x + 1; }

// second padding symbol, same purpose.
int serializeFrame( int x ) { return x + 2; }
