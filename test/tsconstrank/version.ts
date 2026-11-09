// tsconstrank/version.ts — TS-CONST-DEFS V1c: a literal const takes a ranked --for row only when the question names it
// (test/tsshapecheck.sh §9). Shapes taken from microsoft/TypeScript (corePublic.ts version, semver.ts versionRegExp,
// emitter.ts notImplementedResolver).

export const version = "1.2.3";
export const versionRegExp = /^(\d+)\.(\d+)\.(\d+)$/;
export const VERSION_PATTERN = "major.minor.patch";
export const notImplementedResolver = { resolve: (name: string): string | undefined => undefined };

export function printVersion(out: (s: string) => void): void {
    out(`Version ${version}`);
}

export function formatBanner(tool: string): string {
    // the banner names the tool and its version string
    return `${tool} version ${version} (${VERSION_PATTERN})`;
}

export function parseSemver(text: string): number[] {
    const m = versionRegExp.exec(text);
    return m ? m.slice(1).map(Number) : [];
}

export function createResolver(table: Map<string, string>): { resolve(name: string): string | undefined } {
    // a resolver over a fixed table
    return { resolve: (name: string) => table.get(name) };
}
