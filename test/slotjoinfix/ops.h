/* slot-type join fixture (test/slotjoincheck.sh): the struct types, in a header (read by the C++ grammar). */
struct cmd_ent
{
    const char *name;
    int (*exec)( struct cmd_ent *, int );
};
struct mode
{
    void (*command)( int );
    void (*release)( int );
};
struct mode_entry
{
    const struct mode *mode;
    int                x;
};
struct other
{
    int (*exec)( int );
};
struct inner
{
    void (*cb)( int );
};
struct outer
{
    struct inner in;
};
typedef struct mode mode_alias;
struct third
{
    int (*exec)( int );   /* stored below, never called through a `struct third` */
};
