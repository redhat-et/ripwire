/// Café setting: a raw Latin-1 0xE9 byte sits in this doc comment (invalid UTF-8).
int set_cafe_size( int n )
{
    const char* label = "café latin1 body byte";
    (void)label;
    return n + 1;
}
