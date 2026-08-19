// Fixture for test/subtokencheck.sh. Every acronym in this tree is UNREACHABLE by the pre-2026-08-19
// tokenizer, which shredded an all-caps run into 1-byte fragments and then dropped them under the
// >=2-byte rule. The acronyms below are spelled ONLY in capitals anywhere in this fixture, paths
// included, so a query for one of them in lowercase can only be answered through the acronym
// boundary rule -- which is what makes the CLI arm of the gate red before the fix. The gate has a
// presence guard that fails if a later edit ever writes one of them here in lower case.

// Negotiates the MCP session with the host process before any tool call is dispatched.
void negotiateSession( int fd )
{
    if( fd < 0 )
    {
        return;
    }
}

// Paints the widget tree on every frame. Nothing here touches a protocol.
void paintWidgetTree( int frameIndex )
{
    if( frameIndex < 0 )
    {
        return;
    }
}
