#define TAILQ_ENTRY(type) struct { struct type *tqe_next; struct type **tqe_prev; }
