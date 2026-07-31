// svc_api.ts — the service's TS API. cli/ imports it through a tsconfig `paths` alias (@svc/*) that
// resolves into THIS sibling root (DESIGN_multiRoot.md §3.2). The cross-root call edge into svcTsApi
// must appear in the merged workspace graph, and vanish when the alias points at a bogus path.
export function svcTsApi( x: number ): number
{
    return x + 1;
}
