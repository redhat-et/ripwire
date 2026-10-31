/* L-1: a C member written with the name of a C++ smart-pointer alias is a C pointer, never that alias's pointee */
struct OpsIface { int (*run)(int); };
typedef struct OpsIface* SpinPtr;
struct CHolder { SpinPtr ops; };
int cgo(struct CHolder* h) { return h->ops->run(3); }
