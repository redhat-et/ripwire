// A file whose prose describes how resolution works — a conceptual "how does resolution work" query should
// find this via subtoken+body matching ("resolution", "resolve"), not by any single whole-name equality.
int lookupDefinition( int name )
{
    // resolution: match a name to its definition across the scope chain
    return name;
}

// how the resolver resolves a call: it resolves the callee name, then resolves overloads by arity.
void resolveCall()
{
    int resolved = 0;
    (void)resolved;
}
