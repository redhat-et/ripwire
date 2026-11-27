// lexer.cpp — token and space scanning for the record parser.
#include "lexer.h"

int readToken( const std::string& text, int at )
{
    while( at < int( text.size() ) && text[ at ] != ' ' && text[ at ] != '\n' )
    {
        ++at;
    }
    return at;
}

int skipSpace( const std::string& text, int at )
{
    while( at < int( text.size() ) && text[ at ] == ' ' )
    {
        ++at;
    }
    return at;
}
