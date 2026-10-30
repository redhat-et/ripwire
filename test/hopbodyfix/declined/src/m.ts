export interface Matcher { match(x: number): number; }
export class M1 implements Matcher { match(x: number): number { const k1 = x + 1; return k1 * 2; } }
export class M2 implements Matcher { match(x: number): number { const k2 = x + 2; return k2 * 2; } }
export class M3 implements Matcher { match(x: number): number { const k3 = x + 3; return k3 * 2; } }
export class M4 implements Matcher { match(x: number): number { const k4 = x + 4; return k4 * 2; } }
export class M5 implements Matcher { match(x: number): number { const k5 = x + 5; return k5 * 2; } }
export class M6 implements Matcher { match(x: number): number { const k6 = x + 6; return k6 * 2; } }
export class M7 implements Matcher { match(x: number): number { const k7 = x + 7; return k7 * 2; } }
export class M8 implements Matcher { match(x: number): number { const k8 = x + 8; return k8 * 2; } }
export class M9 implements Matcher { match(x: number): number { const k9 = x + 9; return k9 * 2; } }
