// less_than: a < b && "quoted" & <tag>
// doc-comment intentionally hostile to XML serialization (raw <, &, ", tags).
bool less_than( int a, int b )
{
    return a < b;
}

bool uses_less_than( int a, int b )
{
    return less_than( a, b );
}
