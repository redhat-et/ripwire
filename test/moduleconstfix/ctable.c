/* ctable.c — C file-scope const-qualified camel constants (Lang::C arm). */

/* static const camel — must index t="var" post-fix */
static const int k_mc_file_buf_bytes = 4096;

/* plain const pointer camel */
const char* k_mc_file_default_name = "ripwire";

/* NEGATIVE: mutable file-scope camel stays unindexed */
int mc_file_mutable = 2;

int mcUseTable( void )
{
    return k_mc_file_buf_bytes + (int) k_mc_file_default_name[0];
}
