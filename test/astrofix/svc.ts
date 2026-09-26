// The service half of an Astro app: ordinary TypeScript, imported by .astro frontmatter.
// astroSquare is issue #67's case — in this fixture its ONLY caller lives in a .astro file.
export function astroSquare( x: number ): number { return x * x; }

export function astroTwice( x: number ): number { return astroSquare( x ) + 1; }
