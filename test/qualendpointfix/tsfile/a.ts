export class Alpha { run(x: number): number { return x + 1; } }
export class Beta { run(x: number): number { return x * 2; } }
export function driver(): number { return new Alpha().run(1) + new Beta().run(2); }
