// verifyfix/registry.cpp — the dynamic-dispatch-shaped fixture for the unused() mutation arm.
//
// zz_registry_handler is invoked ONLY through a string-keyed registry: its name appears in a string
// literal, never as an identifier reference, so the reference index — which is identifier-based —
// sees ZERO use-sites while the function IS reachable at runtime. An unused(zz_registry_handler)
// verdict must therefore be NOT-ESTABLISHED (the index is a floor), never REFUTED and never CONFIRMED.

// NOTE: mid_hop (defined in chain.cpp) is deliberately mentioned in this comment and nowhere else in
// this file — the defines() extraction-floor arm asserts that a literal occurrence with no extracted
// definition yields NOT-ESTABLISHED, never a confident answer either way.

void invoke_named( const char* name );

// used only via the string below — the index must not see a reference
void zz_registry_handler()
{
}

// the string-keyed call site: "zz_registry_handler" occurs here only as string bytes
void dispatch_by_name()
{
    invoke_named( "zz_registry_handler" );
}
