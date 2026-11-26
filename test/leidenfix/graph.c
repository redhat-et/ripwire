/* test/leidenfix/graph.c — the fixture test/leidencheck.sh runs on. Generated, do not hand-edit the call lists.
 *
 * Fifteen functions lf00..lf14, defined in id order so their symbol ids follow it. The undirected call graph is the
 * 15-node, 23-edge graph a randomized search of ripwire's own local-moving rule (id order, ties to the lower id)
 * found and then minimized edge by edge: plain Louvain local moving ends with the community {lf00, lf01, lf04, lf05},
 * whose two pieces lf00-lf01 and lf04-lf05 were joined only through lf02/lf03 before those moved to another
 * community (Traag, Waltman & van Eck 2019, the bridge-node mechanism). lf12..lf14 is a separate triangle that only
 * adds weight to the modularity denominator; without it the walk takes a different path. Only the UNDIRECTED graph
 * matters, so each edge is called from whichever end keeps every body at two calls or fewer (a longer call list is
 * a clone of every other call sequence in the tree, and --quality-delta says so).
 */
void lf00( void );
void lf01( void );
void lf02( void );
void lf03( void );
void lf04( void );
void lf05( void );
void lf06( void );
void lf07( void );
void lf08( void );
void lf09( void );
void lf10( void );
void lf11( void );
void lf12( void );
void lf13( void );
void lf14( void );

void lf00( void )
{
    lf01();
}

void lf01( void )
{
    lf02();
    lf03();
}

void lf02( void )
{
    lf03();
}

void lf03( void )
{
    lf08();
}

void lf04( void )
{
    lf05();
}

void lf05( void )
{
    lf02();
    lf03();
}

void lf06( void )
{
    lf02();
    lf07();
}

void lf07( void )
{
    lf02();
    lf10();
}

void lf08( void )
{
    lf09();
    lf11();
}

void lf09( void )
{
    lf03();
    lf10();
}

void lf10( void )
{
    lf03();
    lf08();
}

void lf11( void )
{
    lf02();
    lf06();
}

void lf12( void )
{
    lf13();
}

void lf13( void )
{
    lf14();
}

void lf14( void )
{
    lf12();
}
