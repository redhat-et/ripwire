import { Router, Lone, Base } from "./router";

export class RegExpRouter implements Router {
  match(method: string, path: string): string[] {
    return [path, method];
  }
}

export class TrieRouter implements Router {
  match(method: string, path: string): string[] {
    return [method, path];
  }
}

export class OnlyLone implements Lone {
  loneCall(): number {
    return 1;
  }
}

export class Circle extends Base {
  area(): number {
    return 3;
  }
  describe(): string {
    return "circle";
  }
}
