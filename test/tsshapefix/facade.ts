// tsshapefix/facade.ts — the lazy-facade export idiom. openclaw's whole `src/plugin-sdk/` public
// surface is written this way: the exported binding is an arrow WRAPPED in a cast, so the
// declarator's `value:` is an as_expression, not the arrow itself. 103 sites in openclaw, every
// one of them a PUBLIC API entry point — the highest-value symbols in the tree.

interface FacadeModule {
    resolveGatewayEndpoint: ( host: string ) => string;
    buildProviderConfig: ( ...args: unknown[] ) => Record<string, unknown>;
    isFeatureAvailable: () => boolean;
}

declare function loadFacadeModule(): FacadeModule;

// as_expression( parenthesized_expression( arrow_function ) ) — multi-line parameter list, the
// exact shape of src/plugin-sdk/vercel-ai-gateway.ts:30
export const buildProviderConfig: FacadeModule["buildProviderConfig"] = ( (
    ...args: unknown[]
) =>
    loadFacadeModule()["buildProviderConfig"]( ...args ) ) as FacadeModule["buildProviderConfig"];

// the single-line variant
export const resolveGatewayEndpoint: FacadeModule["resolveGatewayEndpoint"] = ( ( host: string ) =>
    loadFacadeModule().resolveGatewayEndpoint( host ) ) as FacadeModule["resolveGatewayEndpoint"];

// zero-parameter form
export const isFeatureAvailable: FacadeModule["isFeatureAvailable"] = ( () =>
    loadFacadeModule().isFeatureAvailable() ) as FacadeModule["isFeatureAvailable"];

// satisfies instead of as — same wrapping problem, different operator
export const describeFacade = ( ( label: string ) => `${ label }-facade` ) satisfies (
    label: string
) => string;

// the UNWRAPPED form, already extracted before this round — pinned so the new patterns are proved
// to be additive rather than a rewrite of the existing one
export const plainArrowExport = ( name: string ): string => `${ name }!`;
