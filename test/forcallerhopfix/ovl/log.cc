#include "log.h"
namespace lg {
void Emit( int code ) { (void)code; }
void Emit( const char* msg ) { (void)msg; }
void Flush() {}
}
