#pragma once
// selectorscopecheck fixture — Box::lid vs Crate::lid: the SAME method name under two different
// scopes, in two files, so a bare-name selector is ambiguous and only the Scope::name spelling —
// the exact sym= spelling --edit-check and --grep's in= rows print — can name one of them.
namespace fixns
{

struct Box
{
    int lid( int x ) { return boxHelper( x ); }
    int boxHelper( int x ) { return x + 1; }
};

}   // namespace fixns
