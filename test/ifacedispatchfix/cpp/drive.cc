#include "runner.h"

bool Builder::startEdge( Edge* e )
{
    return command_runner_->StartCommand( e );
}

bool byPointer( CommandRunner* r, Edge* e )
{
    return r->StartCommand( e );
}

bool byRef( CommandRunner& r )
{
    return r.CanRunMore();
}

int concreteBase( const Shape& s )
{
    return s.area();
}

int soloCall( SoloBase* s )
{
    return s->soloRun( 3 );
}

int hollowCall( Hollow* h )
{
    return h->hollowRun();
}
