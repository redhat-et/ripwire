#include "log.h"
void ReportCode() { lg::Emit( 42 ); }
void ReportText() { lg::Emit( "hello" ); }
void Done() { lg::Flush(); }
int main() { ReportCode(); ReportText(); return 0; }
