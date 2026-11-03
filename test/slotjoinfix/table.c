struct transition
{
    int first;
    int last;
    int (*handler)( int );
};
static int t_print( int c ) { return c; }
static int t_ctrl( int c ) { return -c; }
static const struct transition ground_table[] = { { 0x20, 0x7e, t_print }, { 0x00, 0x1f, t_ctrl } };
int parse( int c )
{
    const struct transition *itr = ground_table;
    return itr->handler( c );
}
static void lay_even( int w ) { (void)w; }
static void lay_main( int w ) { (void)w; }
static const struct
{
    const char *name;
    void (*arrange)( int );
} layouts[] = { { "even", lay_even }, { "main", lay_main } };
void layout_select( int i ) { layouts[i].arrange( i ); }
