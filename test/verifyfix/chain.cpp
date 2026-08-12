// verifyfix/chain.cpp — the call chain the calls()/reaches() arms verify: entry_caller -> mid_hop -> leaf_target.
// dispatch_by_name is DECLARED and CALLED here but DEFINED in registry.cpp (the defines() cross-file arm).

void dispatch_by_name();

// the leaf the chain terminates in — uses()/unused() probe this name
void leaf_target()
{
}

// one hop up
void mid_hop()
{
    leaf_target();
}

// the entry point of the chain
void entry_caller()
{
    mid_hop();
    dispatch_by_name();
}
