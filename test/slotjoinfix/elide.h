// IX-1 fix round 2 (MF-A): a struct typedef and a function-pointer typedef this header declares; elide.c's struct holds them.
typedef struct { int a; int b; } einner_t;
typedef void ( *efp_t )( int );
