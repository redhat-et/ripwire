/* C config translation unit — file-scope SCREAMING_SNAKE constants. */

static const int C_MAX_BUFFER_BYTES = 4096;

static const char* C_DEFAULT_NAME = "ripwire";

static const char* C_DEFAULT_HOSTS[] = { "a.example", "b.example" };

/* lowercase mutable global — must stay unindexed */
int c_mutable_global = 3;

int c_buffer_size( void )
{
    return C_MAX_BUFFER_BYTES;
}
