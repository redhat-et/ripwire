// The control file: its vocabulary is ordinary camelCase and snake_case, reachable by the tokenizer
// both before and after the fix. It is what proves the CLI arm is not inert -- a query aimed here
// must land here on either binary.

#include <cstddef>

// Serializes a payload into the caller's buffer and reports the byte count written.
std::size_t serializePayload( char* out, std::size_t capacity )
{
    if( capacity == 0 )
    {
        return 0;
    }
    out[0] = 0;
    return 1;
}

// Reads a UTF8Encoded run and a sha256sum digest -- the digit-adjacent shapes the unit table pins.
void readDigestRun( const char* utf8EncodedText, const char* sha256sumDigest )
{
    if( utf8EncodedText == nullptr || sha256sumDigest == nullptr )
    {
        return;
    }
}
