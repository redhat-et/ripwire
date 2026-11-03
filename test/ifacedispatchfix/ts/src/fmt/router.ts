export interface Router {
  match(method: string, path: string): string[];
}

export interface Lone {
  loneCall(): number;
}

export abstract class Base {
  abstract area(): number;
  describe(): string {
    return "base";
  }
}
