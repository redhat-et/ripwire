// parser.h — the record parser's three readers.
#pragma once
#include <string>

int parseHeader( const std::string& text, int at );
int parseBody( const std::string& text, int at );
int parseFooter( const std::string& text, int at );
