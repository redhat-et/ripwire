// lexer.h — token and space scanning for the record parser.
#pragma once
#include <string>

int readToken( const std::string& text, int at );
int skipSpace( const std::string& text, int at );
