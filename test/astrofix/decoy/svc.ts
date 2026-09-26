// DECOY. Same basename, same exported name, WRONG directory. page.astro imports "./svc", which is the
// fixture root's svc.ts — this file must never win that edge. A resolver that fell back to a basename
// guess instead of the corpus's own index would bind here, and the gate would catch it.
export function astroSquare( x: number ): number { return x + 1000; }
