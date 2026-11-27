export class Alpha { run(x: number): number { return x + 1; } }
export class Beta { run(x: number): number { return x * 2; } }
export namespace ns { export function make(x: number): number { return x; } }
export namespace other { export function make(x: number): number { return x - 1; } }
function helper(b: Beta): number { return b.run(3); }
export function driver(): number { const a = new Alpha(); return a.run(1) + helper(new Beta()) + ns.make(2); }
