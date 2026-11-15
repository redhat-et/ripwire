#include "reader.h"
struct Parser
{
    FileReader* file_reader_;
    explicit Parser( FileReader* r ) : file_reader_( r ) {}
    int Load( int k );
};
int Parser::Load( int k )
{
    return file_reader_->ReadFile( k );
}
