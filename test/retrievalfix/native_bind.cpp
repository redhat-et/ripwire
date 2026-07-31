int native_checksum( int value )
{
    return value * 31;
}

void register_python_checksum_binding()
{
    native_checksum( 7 );
}
