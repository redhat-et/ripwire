/* zig-step0/measure.c — parse every .zig file under a corpus with the linked
 * tree-sitter-zig and write one TSV row per file.
 *
 * This is the STEP 0 harness for issue #166. It does not extract symbols and it
 * is not a regression gate. The numbers match the parse-health measure ripwire
 * already publishes (src/ingest_crawl.h, measureFileHealth):
 *
 *   - a file is clean when ts_node_has_error(root) is false;
 *   - err_bytes is the sum of the TOP-MOST ERROR spans. Descent stops at an
 *     ERROR node, so nested recovery nodes are not counted twice and the ratio
 *     cannot exceed 1;
 *   - a MISSING node is zero-width, so it makes the file not clean and adds
 *     nothing to err_bytes.
 *
 * A parse that does not finish inside the deadline is a timeout row. It is not
 * counted as clean. The deadline is a progress callback on the vendored
 * tree-sitter core (it has no ts_parser_set_timeout_micros).
 *
 * Usage: zig-step0-measure <corpus-root> <tsv-out> [timeout-ms]
 *
 * TSV, no header, ten tab-separated fields:
 *   path  bytes  status  err_bytes  err_nodes  missing_nodes  first_line
 *   flags  span_head  line
 * status is clean, error, timeout, read_error, or too_big.
 * flags lists dialect keywords found inside the first top-most ERROR span.
 * path is relative to the corpus root. Rows are sorted by path.
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <tree_sitter/api.h>

extern const TSLanguage *tree_sitter_zig( void );

enum { kMaxFileBytes = 64 * 1024 * 1024 };
enum { kSpanHead = 120 };
enum { kLineHead = 160 };

static const char *kWords[] = {
    "usingnamespace", "async", "await", "suspend", "resume", "nosuspend", "anyframe",
};

static char *       g_root    = NULL;
static size_t       g_root_len = 0;
static char **      g_paths   = NULL;
static size_t       g_path_n  = 0;
static size_t       g_path_cap = 0;
static int          g_walk_error = 0;

static uint64_t mono_ns( void )
{
    struct timespec ts;
    clock_gettime( CLOCK_MONOTONIC, &ts );
    return ( uint64_t ) ts.tv_sec * 1000000000ull + ( uint64_t ) ts.tv_nsec;
}

struct Input
{
    const char *data;
    uint32_t    len;
    uint64_t    start_ns;
    uint64_t    limit_ns;
    int         timed_out;
};

static const char *read_input( void *payload, uint32_t byte_index, TSPoint position, uint32_t *bytes_read )
{
    struct Input *in = payload;
    ( void ) position;
    if( byte_index >= in->len )
    {
        *bytes_read = 0;
        return NULL;
    }
    *bytes_read = in->len - byte_index;
    return in->data + byte_index;
}

static bool on_progress( TSParseState *state )
{
    struct Input *in = state->payload;
    if( mono_ns() - in->start_ns > in->limit_ns )
    {
        in->timed_out = 1;
        return true;
    }
    return false;
}

static int is_ident( unsigned char c )
{
    return ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) || c == '_';
}

static int span_has_word( const char *data, uint32_t lo, uint32_t hi, const char *word )
{
    size_t n = strlen( word );
    if( hi < lo || ( uint64_t ) ( hi - lo ) < n )
    {
        return 0;
    }
    for( uint32_t i = lo; i + ( uint32_t ) n <= hi; i++ )
    {
        if( memcmp( data + i, word, n ) != 0 )
        {
            continue;
        }
        int left_ok  = ( i == lo ) || !is_ident( ( unsigned char ) data[ i - 1 ] );
        int right_ok = ( i + ( uint32_t ) n == hi ) || !is_ident( ( unsigned char ) data[ i + ( uint32_t ) n ] );
        if( left_ok && right_ok )
        {
            return 1;
        }
    }
    return 0;
}

/* Collapse controls to spaces and cap the length so a TSV cell stays one line. */
static void sanitize( const char *data, uint32_t lo, uint32_t hi, char *out, size_t out_cap )
{
    if( out_cap == 0 )
    {
        return;
    }
    size_t w = 0;
    int    sp = 1;
    if( hi < lo )
    {
        hi = lo;
    }
    for( uint32_t i = lo; i < hi && w + 1 < out_cap; i++ )
    {
        unsigned char c = ( unsigned char ) data[ i ];
        if( c < 32 || c == 127 || c == '\t' )
        {
            c = ' ';
        }
        if( c == ' ' )
        {
            if( sp )
            {
                continue;
            }
            sp = 1;
        }
        else
        {
            sp = 0;
        }
        out[ w++ ] = ( char ) c;
    }
    while( w > 0 && out[ w - 1 ] == ' ' )
    {
        w--;
    }
    out[ w ] = '\0';
}

struct Walk
{
    const char *data;
    uint32_t    len;
    uint64_t    err_bytes;
    uint32_t    err_nodes;
    uint32_t    missing_nodes;
    uint32_t    first_lo;
    uint32_t    first_hi;
    uint32_t    first_line;
    int         have_first;
    uint32_t    missing_lo;
    uint32_t    missing_line;
    int         have_missing;
    char        missing_type[ 64 ];
    TSTreeCursor *stack;
    size_t       stack_n;
    size_t       stack_cap;
};

static int push_cursor( struct Walk *w, TSTreeCursor cur )
{
    if( w->stack_n == w->stack_cap )
    {
        size_t ncap = w->stack_cap ? w->stack_cap * 2 : 64;
        TSTreeCursor *grown = realloc( w->stack, ncap * sizeof( *grown ) );
        if( grown == NULL )
        {
            ts_tree_cursor_delete( &cur );
            return -1;
        }
        w->stack = grown;
        w->stack_cap = ncap;
    }
    /* Ownership of this cursor moves into the stack. Bitwise move is safe
     * only because the caller never deletes the source. Copies that must
     * outlive the source go through ts_tree_cursor_copy. */
    w->stack[ w->stack_n++ ] = cur;
    return 0;
}

static void drain_cursors( struct Walk *w )
{
    while( w->stack_n > 0 )
    {
        TSTreeCursor cur = w->stack[ --w->stack_n ];
        ts_tree_cursor_delete( &cur );
    }
}

static int account_tree( struct Walk *w, TSNode root )
{
    TSTreeCursor root_cur = ts_tree_cursor_new( root );
    if( push_cursor( w, root_cur ) != 0 )
    {
        return -1;
    }
    while( w->stack_n > 0 )
    {
        TSTreeCursor cur = w->stack[ --w->stack_n ];
        TSNode       node = ts_tree_cursor_current_node( &cur );
        if( ts_node_is_null( node ) )
        {
            ts_tree_cursor_delete( &cur );
            continue;
        }
        if( ts_node_is_error( node ) )
        {
            uint32_t lo = ts_node_start_byte( node );
            uint32_t hi = ts_node_end_byte( node );
            if( lo > w->len )
            {
                lo = w->len;
            }
            if( hi > w->len )
            {
                hi = w->len;
            }
            w->err_nodes++;
            if( hi > lo )
            {
                w->err_bytes += ( uint64_t ) ( hi - lo );
            }
            if( !w->have_first || lo < w->first_lo )
            {
                TSPoint p = ts_node_start_point( node );
                w->have_first = 1;
                w->first_lo = lo;
                w->first_hi = hi;
                w->first_line = p.row + 1;
            }
            ts_tree_cursor_delete( &cur );
            continue; /* top-most only */
        }
        if( ts_node_is_missing( node ) )
        {
            uint32_t lo = ts_node_start_byte( node );
            if( lo > w->len )
            {
                lo = w->len;
            }
            w->missing_nodes++;
            if( !w->have_missing || lo < w->missing_lo )
            {
                const char *ty = ts_node_type( node );
                TSPoint     p = ts_node_start_point( node );
                w->have_missing = 1;
                w->missing_lo = lo;
                w->missing_line = p.row + 1;
                snprintf( w->missing_type, sizeof( w->missing_type ), "%s", ty != NULL ? ty : "?" );
            }
            ts_tree_cursor_delete( &cur );
            continue;
        }
        int pushed = 0;
        if( ts_tree_cursor_goto_first_child( &cur ) )
        {
            for( ;; )
            {
                TSNode child = ts_tree_cursor_current_node( &cur );
                if( ts_node_has_error( child ) || ts_node_is_missing( child ) )
                {
                    if( push_cursor( w, ts_tree_cursor_copy( &cur ) ) != 0 )
                    {
                        ts_tree_cursor_delete( &cur );
                        drain_cursors( w );
                        return -1;
                    }
                    pushed = 1;
                }
                if( !ts_tree_cursor_goto_next_sibling( &cur ) )
                {
                    break;
                }
            }
        }
        /* ts_node_has_error is error_cost > 0, which is wider than an ERROR
         * or MISSING node. An empty `enum {}` is a zero-width identifier with
         * that cost and neither flag. Record the leaf so the row is not blank. */
        if( !pushed && ts_node_has_error( node ) )
        {
            uint32_t lo = ts_node_start_byte( node );
            if( lo > w->len )
            {
                lo = w->len;
            }
            if( !w->have_missing || lo < w->missing_lo )
            {
                const char *ty = ts_node_type( node );
                TSPoint     p = ts_node_start_point( node );
                w->have_missing = 1;
                w->missing_lo = lo;
                w->missing_line = p.row + 1;
                snprintf( w->missing_type, sizeof( w->missing_type ), "cost %s", ty != NULL ? ty : "?" );
            }
        }
        ts_tree_cursor_delete( &cur );
    }
    return 0;
}

static int collect( const char *fpath, const struct stat *sb, int typeflag, struct FTW *ftw )
{
    ( void ) sb;
    ( void ) ftw;
    const char *slash = strrchr( fpath, '/' );
    const char *base = slash ? slash + 1 : fpath;
    /* FTW_ACTIONRETVAL is set on the nftw call, so these return values
     * steer the walk. A plain non-zero return would stop it. */
    if( typeflag == FTW_D )
    {
        if( strcmp( base, ".git" ) == 0 )
        {
            return FTW_SKIP_SUBTREE;
        }
        return FTW_CONTINUE;
    }
    if( typeflag != FTW_F )
    {
        return FTW_CONTINUE;
    }
    size_t bl = strlen( base );
    if( bl < 4 || strcmp( base + bl - 4, ".zig" ) != 0 )
    {
        return FTW_CONTINUE;
    }
    if( g_path_n == g_path_cap )
    {
        size_t ncap = g_path_cap ? g_path_cap * 2 : 256;
        char **grown = realloc( g_paths, ncap * sizeof( *grown ) );
        if( grown == NULL )
        {
            g_walk_error = 1;
            return FTW_STOP;
        }
        g_paths = grown;
        g_path_cap = ncap;
    }
    g_paths[ g_path_n ] = strdup( fpath );
    if( g_paths[ g_path_n ] == NULL )
    {
        g_walk_error = 1;
        return FTW_STOP;
    }
    g_path_n++;
    return FTW_CONTINUE;
}

static int cmp_path( const void *a, const void *b )
{
    const char * const *sa = a;
    const char * const *sb = b;
    return strcmp( *sa, *sb );
}

static const char *relative_path( const char *full )
{
    if( strncmp( full, g_root, g_root_len ) == 0 && full[ g_root_len ] == '/' )
    {
        return full + g_root_len + 1;
    }
    return full;
}

static void write_row( FILE *out, const char *path, uint64_t bytes, const char *status,
                       uint64_t err_bytes, uint32_t err_nodes, uint32_t missing_nodes,
                       const char *first_line, const char *flags, const char *span, const char *line )
{
    fprintf( out, "%s\t%llu\t%s\t%llu\t%u\t%u\t%s\t%s\t%s\t%s\n",
             path,
             ( unsigned long long ) bytes,
             status,
             ( unsigned long long ) err_bytes,
             err_nodes,
             missing_nodes,
             first_line,
             flags,
             span,
             line );
}

static int measure_one( TSParser *parser, const char *full, uint64_t limit_ns, FILE *out )
{
    const char *rel = relative_path( full );
    int         fd = open( full, O_RDONLY );
    if( fd < 0 )
    {
        write_row( out, rel, 0, "read_error", 0, 0, 0, "", "", "", "" );
        return 0;
    }
    struct stat st;
    if( fstat( fd, &st ) != 0 || !S_ISREG( st.st_mode ) )
    {
        close( fd );
        write_row( out, rel, 0, "read_error", 0, 0, 0, "", "", "", "" );
        return 0;
    }
    if( st.st_size < 0 || ( uint64_t ) st.st_size > kMaxFileBytes || ( uint64_t ) st.st_size > 0xffffffffull )
    {
        close( fd );
        write_row( out, rel, ( uint64_t ) st.st_size, "too_big", 0, 0, 0, "", "", "", "" );
        return 0;
    }
    uint32_t len = ( uint32_t ) st.st_size;
    char *   data = malloc( ( size_t ) len + 1 );
    if( data == NULL )
    {
        close( fd );
        fprintf( stderr, "out of memory reading %s\n", rel );
        return -1;
    }
    uint32_t got = 0;
    while( got < len )
    {
        ssize_t n = read( fd, data + got, len - got );
        if( n < 0 )
        {
            if( errno == EINTR )
            {
                continue;
            }
            free( data );
            close( fd );
            write_row( out, rel, len, "read_error", 0, 0, 0, "", "", "", "" );
            return 0;
        }
        if( n == 0 )
        {
            break;
        }
        got += ( uint32_t ) n;
    }
    close( fd );
    if( got != len )
    {
        free( data );
        write_row( out, rel, len, "read_error", 0, 0, 0, "", "", "", "" );
        return 0;
    }
    data[ len ] = '\0';

    struct Input in;
    in.data = data;
    in.len = len;
    in.start_ns = mono_ns();
    in.limit_ns = limit_ns;
    in.timed_out = 0;

    TSInput input;
    memset( &input, 0, sizeof( input ) );
    input.payload = &in;
    input.read = read_input;
    input.encoding = TSInputEncodingUTF8;

    TSParseOptions opt;
    memset( &opt, 0, sizeof( opt ) );
    opt.payload = &in;
    opt.progress_callback = on_progress;

    TSTree *tree = ts_parser_parse_with_options( parser, NULL, input, opt );
    ts_parser_reset( parser );
    if( tree == NULL )
    {
        free( data );
        write_row( out, rel, len, "timeout", 0, 0, 0, "", "", "", "" );
        fprintf( stderr, "timeout %s (%u bytes)\n", rel, len );
        return 0;
    }

    TSNode root = ts_tree_root_node( tree );
    int    has_error = ts_node_has_error( root );
    struct Walk w;
    memset( &w, 0, sizeof( w ) );
    w.data = data;
    w.len = len;
    if( has_error && account_tree( &w, root ) != 0 )
    {
        ts_tree_delete( tree );
        free( w.stack );
        free( data );
        fprintf( stderr, "out of memory walking %s\n", rel );
        return -1;
    }
    ts_tree_delete( tree );
    free( w.stack );

    if( w.err_bytes > len )
    {
        fprintf( stderr, "harness bug: err_bytes %llu > file %u in %s\n",
                 ( unsigned long long ) w.err_bytes, len, rel );
        free( data );
        return -1;
    }

    char line_no[ 32 ] = "";
    char flags[ 256 ] = "";
    char span[ kSpanHead ] = "";
    char line[ kLineHead ] = "";
    if( w.have_first )
    {
        snprintf( line_no, sizeof( line_no ), "%u", w.first_line );
        uint32_t span_hi = w.first_lo + kSpanHead - 1;
        if( span_hi > w.first_hi )
        {
            span_hi = w.first_hi;
        }
        sanitize( data, w.first_lo, span_hi, span, sizeof( span ) );

        uint32_t ls = w.first_lo;
        while( ls > 0 && data[ ls - 1 ] != '\n' )
        {
            ls--;
        }
        uint32_t le = w.first_lo;
        while( le < len && data[ le ] != '\n' )
        {
            le++;
        }
        /* Keep the excerpt near the error when the line is huge. */
        if( le - ls > kLineHead - 1 )
        {
            uint32_t window = kLineHead - 1;
            if( w.first_lo > ls + window / 2 )
            {
                ls = w.first_lo - window / 2;
            }
            if( ls + window < le )
            {
                le = ls + window;
            }
        }
        sanitize( data, ls, le, line, sizeof( line ) );

        size_t fl = 0;
        for( size_t i = 0; i < sizeof( kWords ) / sizeof( kWords[ 0 ] ); i++ )
        {
            if( !span_has_word( data, w.first_lo, w.first_hi, kWords[ i ] ) )
            {
                continue;
            }
            size_t n = strlen( kWords[ i ] );
            if( fl + n + 2 >= sizeof( flags ) )
            {
                break;
            }
            if( fl > 0 )
            {
                flags[ fl++ ] = ',';
            }
            memcpy( flags + fl, kWords[ i ], n );
            fl += n;
            flags[ fl ] = '\0';
        }
    }
    else if( w.have_missing )
    {
        /* No ERROR bytes. Say which token the parser inserted, and the line
         * it inserted it on, so a zero-width miss is not an empty row. */
        snprintf( line_no, sizeof( line_no ), "%u", w.missing_line );
        char raw[ 96 ];
        if( strncmp( w.missing_type, "cost ", 5 ) == 0 )
        {
            snprintf( raw, sizeof( raw ), "%s", w.missing_type );
        }
        else
        {
            snprintf( raw, sizeof( raw ), "MISSING %s", w.missing_type );
        }
        sanitize( raw, 0, ( uint32_t ) strlen( raw ), span, sizeof( span ) );
        uint32_t ls = w.missing_lo;
        while( ls > 0 && data[ ls - 1 ] != '\n' )
        {
            ls--;
        }
        uint32_t le = w.missing_lo;
        while( le < len && data[ le ] != '\n' )
        {
            le++;
        }
        if( le - ls > kLineHead - 1 )
        {
            uint32_t window = kLineHead - 1;
            if( w.missing_lo > ls + window / 2 )
            {
                ls = w.missing_lo - window / 2;
            }
            if( ls + window < le )
            {
                le = ls + window;
            }
        }
        sanitize( data, ls, le, line, sizeof( line ) );
    }

    const char *status = has_error ? "error" : "clean";
    write_row( out, rel, len, status, w.err_bytes, w.err_nodes, w.missing_nodes, line_no, flags, span, line );
    free( data );
    return 0;
}

int main( int argc, char **argv )
{
    if( argc < 3 || argc > 4 )
    {
        fprintf( stderr, "usage: %s <corpus-root> <tsv-out> [timeout-ms]\n", argv[ 0 ] );
        return 2;
    }
    uint64_t timeout_ms = 10000;
    if( argc == 4 )
    {
        char *end = NULL;
        unsigned long v = strtoul( argv[ 3 ], &end, 10 );
        if( end == argv[ 3 ] || *end != '\0' || v == 0 || v > 600000ul )
        {
            fprintf( stderr, "bad timeout-ms\n" );
            return 2;
        }
        timeout_ms = v;
    }
    uint64_t limit_ns = timeout_ms * 1000000ull;

    g_root = argv[ 1 ];
    size_t rl = strlen( g_root );
    while( rl > 1 && g_root[ rl - 1 ] == '/' )
    {
        g_root[ --rl ] = '\0';
    }
    g_root_len = rl;

    const TSLanguage *lang = tree_sitter_zig();
    uint32_t abi = ts_language_abi_version( lang );
    fprintf( stderr, "abi %u\n", abi );

    TSParser *parser = ts_parser_new();
    if( parser == NULL || !ts_parser_set_language( parser, lang ) )
    {
        fprintf( stderr, "ts_parser_set_language failed (abi %u, core accepts %d..%d)\n",
                 abi, TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION, TREE_SITTER_LANGUAGE_VERSION );
        ts_parser_delete( parser );
        return 1;
    }

    g_walk_error = 0;
    if( nftw( g_root, collect, 64, FTW_PHYS | FTW_ACTIONRETVAL ) == -1 || g_walk_error )
    {
        perror( g_root );
        ts_parser_delete( parser );
        return 1;
    }
    qsort( g_paths, g_path_n, sizeof( *g_paths ), cmp_path );

    FILE *out = fopen( argv[ 2 ], "w" );
    if( out == NULL )
    {
        perror( argv[ 2 ] );
        ts_parser_delete( parser );
        return 1;
    }

    for( size_t i = 0; i < g_path_n; i++ )
    {
        if( measure_one( parser, g_paths[ i ], limit_ns, out ) != 0 )
        {
            fclose( out );
            ts_parser_delete( parser );
            return 1;
        }
        if( ( i + 1 ) % 250 == 0 )
        {
            fprintf( stderr, "parsed %zu / %zu\n", i + 1, g_path_n );
        }
        free( g_paths[ i ] );
        g_paths[ i ] = NULL;
    }
    free( g_paths );
    g_paths = NULL;
    if( fclose( out ) != 0 )
    {
        perror( argv[ 2 ] );
        ts_parser_delete( parser );
        return 1;
    }
    ts_parser_delete( parser );
    fprintf( stderr, "files %zu\n", g_path_n );
    return 0;
}
