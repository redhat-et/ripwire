// tsshapefix/typeimport.ts — the LARGEST disclosed TypeScript limit, and the only one that is not
// ours to fix in a .scm: the vendored tree-sitter-typescript (pinned v0.23.2 in CMakeLists.txt)
// cannot parse `typeof import("…")` once it appears in a NESTED type position. Measured on
// openclaw 2026-08-04: 1 222 of 24 658 .ts files (5.0 %) contain at least one such site.
//
// Parses fine (kept here as the control — a regression that broke THESE would be ours):
//   type A = typeof import("./m.js").thing;      // type-alias RHS, top level
//   type B = import("./m.js").Thing;             // import type, top level
//
// Does NOT parse — the two shapes the corpus actually uses:
//   (typeof import("./m.js").things)[number]     // inside a parenthesized_type      235 sites
//   f<typeof import("./m.js")>()                 // inside a call's type arguments  2 087 sites
//
// THE MEASURED COST IS MUCH SMALLER THAN THE SITE COUNT, and saying so is the point of this file.
// tree-sitter error recovery scopes the damage to the ENCLOSING DECLARATION, not the file: across
// all 1 222 affected files the total loss is ~15 definitions out of 261 760 (type-alias recall
// 1 607/1 614 and function recall 6 805/6 813 inside the affected files themselves). The
// type-ARGUMENT form costs essentially nothing, because it occurs inside expressions and bodies
// whose enclosing definition still parses. Only a leading broken statement — nothing before it to
// anchor recovery on — can cost a whole file. That is why this limit is DISCLOSED rather than paid
// for with a grammar-pin bump, which would re-baseline every .ts/.tsx symbol in the tree to buy
// back fifteen rows. This fixture pins the shape of that containment: survivors on both sides.

export function survivesBeforeTypeImport(): number
{
    return 1;
}

// control: the two forms the pinned grammar DOES handle
export type ControlTypeofImport = typeof import( "./facade.js" ).plainArrowExport;
export type ControlImportType = import( "./facade.js" ).FacadeModuleShape;

export function alsoSurvivesBeforeTheHole(): number
{
    return 2;
}

// ── the hole ─────────────────────────────────────────────────────────────────────────────────────
// KNOWN LIMIT (grammar pin): parenthesized type wrapping `typeof import(…)`
export type BrokenParenthesized = ( typeof import( "./facade.js" ).plainArrowExport )[keyof string];

// KNOWN LIMIT (grammar pin): `typeof import(…)` as an explicit call type argument — the vitest
// `importOriginal<typeof import("…")>()` idiom, 2 087 sites in openclaw
export async function brokenTypeArgument( importOriginal: <T>() => Promise<T> )
{
    const actual = await importOriginal<typeof import( "./facade.js" )>();
    return actual;
}
// ─────────────────────────────────────────────────────────────────────────────────────────────────

export function survivesAfterTypeImport(): number
{
    return 3;
}
