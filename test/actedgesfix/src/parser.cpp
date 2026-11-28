// parser.cpp — the record parser: a header, a body and a footer, each read token by token.
#include "lexer.h"

#include <string>

int parseHeader( const std::string& text, int at )
{
    at = skipSpace( text, at );
    while( at < int( text.size() ) && text[ at ] != '\n' )
    {
        at = readToken( text, at );
    }
    return at + 1;
}

int parseBody( const std::string& text, int at )
{
    at = skipSpace( text, at );
    while( at < int( text.size() ) && text[ at ] != '#' )
    {
        at = readToken( text, at );
        at = skipSpace( text, at );
    }
    return at;
}

int parseFooter( const std::string& text, int at )
{
    at = skipSpace( text, at );
    if( at < int( text.size() ) && text[ at ] == '#' )
    {
        at = readToken( text, at + 1 );
    }
    return at;
}
