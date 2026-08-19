// The ACRONYMWord half of the fixture: HTTPServerBinder must split into three tokens, the first of
// which is the acronym in lower case. That word is spelled nowhere else in this tree, in any case,
// so a query for it reaches this file only if the acronym-run boundary rule is live.

// Binds and listens on behalf of the embedded server.
class HTTPServerBinder
{
public:
    // Opens the listening socket for the configured port.
    bool bindListenSocket( int port );

private:
    int listeningPort = 0;
};

bool HTTPServerBinder::bindListenSocket( int port )
{
    listeningPort = port;
    return port > 0;
}
